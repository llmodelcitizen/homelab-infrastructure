#!/usr/bin/env python3
"""Parallel Docker image updater with Rich terminal UI."""

import argparse
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path

import docker
import yaml
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.progress_bar import ProgressBar
from rich.table import Table
from rich.text import Text

SERVICES_DIR = Path(__file__).resolve().parent


@dataclass
class BuildContext:
    compose_service: str  # e.g. "prowlarr"
    context_path: Path  # e.g. services/arr/prowlarr-patch
    tag: str  # e.g. "arr-prowlarr" (matches compose project naming)


@dataclass
class Service:
    name: str
    path: Path
    ctl: Path
    images: list[str] = field(default_factory=list)
    builds: list[BuildContext] = field(default_factory=list)


def parse_image_ref(ref: str) -> tuple[str, str]:
    """Split image reference into (repository, tag).

    Handles registry URLs — the part after the last colon is only a tag
    if it contains no slashes.
    """
    last_colon = ref.rfind(":")
    if last_colon != -1 and "/" not in ref[last_colon + 1 :]:
        return ref[:last_colon], ref[last_colon + 1 :]
    return ref, "latest"


def discover_services(names: list[str] | None = None) -> list[Service]:
    """Scan services directory for directories with docker-compose.yml + *ctl."""
    services = []
    for d in sorted(SERVICES_DIR.iterdir()):
        if not d.is_dir():
            continue
        compose_file = d / "docker-compose.yml"
        if not compose_file.exists():
            continue
        ctls = list(d.glob("*ctl"))
        if not ctls:
            continue
        if names and d.name not in names:
            continue

        svc = Service(name=d.name, path=d, ctl=ctls[0])

        with open(compose_file) as f:
            compose = yaml.safe_load(f)

        for cs_name, cs_def in (compose.get("services") or {}).items():
            if "image" in cs_def:
                svc.images.append(cs_def["image"])
            if "build" in cs_def:
                build_def = cs_def["build"]
                context_dir = build_def if isinstance(build_def, str) else build_def.get("context", ".")
                context_path = (d / context_dir).resolve()
                svc.builds.append(
                    BuildContext(
                        compose_service=cs_name,
                        context_path=context_path,
                        tag=f"{d.name}-{cs_name}",
                    )
                )
                # Pre-pull base images from Dockerfile
                dockerfile = context_path / "Dockerfile"
                if dockerfile.exists():
                    for line in dockerfile.read_text().splitlines():
                        m = re.match(r"^\s*FROM\s+(\S+)", line, re.IGNORECASE)
                        if m and m.group(1).lower() != "scratch":
                            svc.images.append(m.group(1))

        services.append(svc)
    return services


# --- Result types ---


@dataclass
class PullResult:
    image: str
    status: str  # updated | current | failed
    elapsed: float
    error: str = ""


@dataclass
class BuildResult:
    tag: str
    status: str  # built | failed
    elapsed: float
    error: str = ""


@dataclass
class RecreateResult:
    service: str
    status: str  # done | failed
    elapsed: float
    error: str = ""


# --- Workers ---


def pull_image(client: docker.DockerClient, image: str) -> PullResult:
    """Pull a single image, detecting whether it was updated."""
    start = time.monotonic()
    repo, tag = parse_image_ref(image)
    try:
        old_id = None
        try:
            old_id = client.images.get(f"{repo}:{tag}").id
        except docker.errors.ImageNotFound:
            pass

        new_img = client.images.pull(repo, tag=tag)
        elapsed = time.monotonic() - start

        if old_id and new_img.id == old_id:
            return PullResult(image, "current", elapsed)
        return PullResult(image, "updated", elapsed)
    except Exception as e:
        return PullResult(image, "failed", time.monotonic() - start, str(e))


def build_image(client: docker.DockerClient, bc: BuildContext) -> BuildResult:
    """Build a Docker image from a build context."""
    start = time.monotonic()
    try:
        client.images.build(path=str(bc.context_path), tag=bc.tag, pull=True, rm=True)
        return BuildResult(bc.tag, "built", time.monotonic() - start)
    except Exception as e:
        return BuildResult(bc.tag, "failed", time.monotonic() - start, str(e))


def recreate_service(svc: Service) -> RecreateResult:
    """Run ctl up -d for a service."""
    start = time.monotonic()
    try:
        result = subprocess.run(
            [str(svc.ctl), "up", "-d"],
            cwd=str(svc.path),
            capture_output=True,
            text=True,
            timeout=120,
        )
        elapsed = time.monotonic() - start
        if result.returncode != 0:
            return RecreateResult(svc.name, "failed", elapsed, result.stderr.strip())
        return RecreateResult(svc.name, "done", elapsed)
    except Exception as e:
        return RecreateResult(svc.name, "failed", time.monotonic() - start, str(e))


# --- Rich display ---

STATUS_STYLE = {
    "updated": ("updated", "green bold"),
    "current": ("current", "dim"),
    "built": ("built", "green bold"),
    "done": ("done", "green"),
    "failed": ("FAILED", "red bold"),
}


def _status_cell(status: str | None, in_progress_label: str) -> Text:
    if status is None:
        return Text(in_progress_label, style="yellow")
    label, style = STATUS_STYLE.get(status, (status, ""))
    return Text(label, style=style)


def _time_cell(elapsed: float | None) -> str:
    return f"{elapsed:.1f}s" if elapsed is not None else "-"


def make_phase1_display(
    pull_results: dict[str, PullResult | None],
    build_results: dict[str, BuildResult | None],
) -> Group:
    total = len(pull_results) + len(build_results)
    completed = sum(1 for r in pull_results.values() if r is not None) + sum(
        1 for r in build_results.values() if r is not None
    )

    header = Text.assemble(("Pulling images ", "bold"), (f"{completed}/{total}", "bold cyan"))
    bar = ProgressBar(total=max(total, 1), completed=completed, width=50)

    table = Table(show_header=True, show_edge=False, pad_edge=False)
    table.add_column("Image", style="cyan", min_width=45, no_wrap=True)
    table.add_column("Status", min_width=10)
    table.add_column("Time", justify="right", min_width=7)

    for image in sorted(pull_results):
        r = pull_results[image]
        table.add_row(
            image,
            _status_cell(r.status if r else None, "pulling..."),
            _time_cell(r.elapsed if r else None),
        )

    for tag in sorted(build_results):
        r = build_results[tag]
        table.add_row(
            f"(build) {tag}",
            _status_cell(r.status if r else None, "building..."),
            _time_cell(r.elapsed if r else None),
        )

    return Group(header, bar, Text(""), table)


def make_phase2_display(recreate_results: dict[str, RecreateResult | None | str]) -> Table:
    table = Table(show_header=True, show_edge=False, pad_edge=False)
    table.add_column("Service", style="cyan", min_width=25)
    table.add_column("Status", min_width=12)
    table.add_column("Time", justify="right", min_width=7)

    for name in sorted(recreate_results):
        val = recreate_results[name]
        if isinstance(val, str):  # "waiting"
            table.add_row(name, Text("waiting", style="dim"), "-")
        elif val is None:  # in progress
            table.add_row(name, Text("recreating...", style="yellow"), "-")
        else:
            table.add_row(name, _status_cell(val.status, "recreating..."), _time_cell(val.elapsed))

    return table


# --- Main ---


def main():
    parser = argparse.ArgumentParser(description="Update Docker services with parallel image pulls")
    parser.add_argument("services", nargs="+", help="Service names to update, or 'all'")
    parser.add_argument("--pull-only", action="store_true", help="Pull/build only, skip recreation")
    parser.add_argument("--workers", type=int, default=8, help="Parallel workers (default: 8)")
    args = parser.parse_args()

    console = Console()

    # Service discovery
    names = None if "all" in args.services else args.services
    services = discover_services(names)

    if not services:
        console.print("[red]No matching services found[/red]")
        sys.exit(1)

    if names:
        found = {s.name for s in services}
        missing = set(names) - found
        if missing:
            console.print(f"[red]Services not found: {', '.join(sorted(missing))}[/red]")
            sys.exit(1)

    console.print(Panel(", ".join(s.name for s in services), title=f"Updating {len(services)} services"))

    # Connect to Docker
    try:
        client = docker.from_env()
        client.ping()
    except docker.errors.DockerException as e:
        console.print(f"[red]Cannot connect to Docker: {e}[/red]")
        sys.exit(1)

    overall_start = time.monotonic()
    failures: list[str] = []

    # Collect unique images and all build contexts
    all_images: list[str] = []
    seen: set[str] = set()
    all_builds: list[BuildContext] = []

    for svc in services:
        for img in svc.images:
            repo, tag = parse_image_ref(img)
            key = f"{repo}:{tag}"
            if key not in seen:
                seen.add(key)
                all_images.append(key)
        all_builds.extend(svc.builds)

    # Phase 1: parallel pull + build
    pull_results: dict[str, PullResult | None] = {img: None for img in all_images}
    build_results: dict[str, BuildResult | None] = {bc.tag: None for bc in all_builds}

    if all_images or all_builds:
        console.print()
        with Live(console=console, refresh_per_second=8) as live:
            live.update(make_phase1_display(pull_results, build_results))

            with ThreadPoolExecutor(max_workers=args.workers) as executor:
                futures = {}
                for img in all_images:
                    futures[executor.submit(pull_image, client, img)] = ("pull", img)
                for bc in all_builds:
                    futures[executor.submit(build_image, client, bc)] = ("build", bc.tag)

                for fut in as_completed(futures):
                    kind, key = futures[fut]
                    result = fut.result()
                    if kind == "pull":
                        pull_results[key] = result
                        if result.status == "failed":
                            failures.append(f"pull {key}: {result.error}")
                    else:
                        build_results[key] = result
                        if result.status == "failed":
                            failures.append(f"build {key}: {result.error}")
                    live.update(make_phase1_display(pull_results, build_results))

    updated_count = sum(1 for r in pull_results.values() if r and r.status == "updated")
    built_count = sum(1 for r in build_results.values() if r and r.status == "built")

    # Phase 2: sequential recreate
    if not args.pull_only:
        console.print()
        console.print("[bold]Recreating containers[/bold]")
        console.print()

        recreate_results: dict[str, RecreateResult | None | str] = {s.name: "waiting" for s in services}

        with Live(make_phase2_display(recreate_results), console=console, refresh_per_second=4) as live:
            for svc in services:
                recreate_results[svc.name] = None  # in progress
                live.update(make_phase2_display(recreate_results))

                result = recreate_service(svc)
                recreate_results[svc.name] = result
                if result.status == "failed":
                    failures.append(f"recreate {svc.name}: {result.error}")
                live.update(make_phase2_display(recreate_results))

    # Summary
    elapsed = time.monotonic() - overall_start
    console.print()

    svc_count = len(services)
    parts = [f"{svc_count}/{svc_count} services"]
    if updated_count:
        parts.append(f"{updated_count} images updated")
    if built_count:
        parts.append(f"{built_count} images built")
    if args.pull_only:
        parts.append("pull only")

    summary = f"{', '.join(parts)} in {elapsed:.1f}s"

    if failures:
        console.print(Panel(summary, title="Done (with errors)", border_style="red"))
        console.print()
        for fail in failures:
            console.print(f"  [red]{fail}[/red]")
        console.print()
        sys.exit(1)
    else:
        console.print(Panel(summary, title="Done", border_style="green"))


if __name__ == "__main__":
    main()
