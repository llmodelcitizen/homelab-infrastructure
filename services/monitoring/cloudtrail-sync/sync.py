#!/usr/bin/env python3
"""Sync CloudTrail logs from S3, convert to NDJSON, and enrich with WHOIS org."""

import gzip
import ipaddress
import json
import logging
import os
import subprocess
import time
from pathlib import Path

logging.basicConfig(
    format="%(asctime)s %(levelname)s %(message)s",
    level=logging.INFO,
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger("cloudtrail-sync")

S3_BUCKET = os.environ["S3_BUCKET"]
S3_PREFIX = os.environ["S3_PREFIX"]
SYNC_INTERVAL = int(os.environ.get("SYNC_INTERVAL", "300"))

RAW_DIR = Path("/data/raw")
NDJSON_DIR = Path("/data/ndjson")
IP_CACHE_FILE = Path("/data/ip-cache.json")
ENRICHED_SENTINEL = Path("/data/.enriched")


def load_ip_cache() -> dict[str, str]:
    if IP_CACHE_FILE.exists():
        return json.loads(IP_CACHE_FILE.read_text())
    return {}


def save_ip_cache(cache: dict[str, str]):
    IP_CACHE_FILE.write_text(json.dumps(cache, indent=2))


def is_ip(value: str) -> bool:
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return False


def lookup_ip_org(ip: str) -> str:
    """Resolve IP to owning org via Team Cymru DNS-based ASN lookup."""
    reversed_ip = ".".join(reversed(ip.split(".")))
    try:
        # Step 1: IP -> ASN
        result = subprocess.run(
            ["dig", "+short", "+timeout=3", "+tries=1",
             f"{reversed_ip}.origin.asn.cymru.com", "TXT"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return "Unknown"

        # Parse: "15169 | 8.8.8.0/24 | US | arin | 2023-12-28"
        asn = result.stdout.strip().strip('"').split("|")[0].strip()
        if not asn:
            return "Unknown"

        # Step 2: ASN -> org name
        result = subprocess.run(
            ["dig", "+short", "+timeout=3", "+tries=1",
             f"AS{asn}.asn.cymru.com", "TXT"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return "Unknown"

        # Parse: "15169 | US | arin | 2000-03-30 | GOOGLE, US"
        parts = result.stdout.strip().strip('"').split("|")
        if len(parts) >= 5:
            return parts[4].strip()
    except (subprocess.TimeoutExpired, Exception) as e:
        log.warning("WHOIS lookup failed for %s: %s", ip, e)

    return "Unknown"


def resolve_ips(ips: set[str], cache: dict[str, str]) -> dict[str, str]:
    """Look up any uncached IPs and return the updated cache."""
    new_ips = {ip for ip in ips if is_ip(ip) and ip not in cache}
    if not new_ips:
        return cache

    log.info("Looking up %d new IPs...", len(new_ips))
    for ip in sorted(new_ips):
        org = lookup_ip_org(ip)
        cache[ip] = org
        log.info("  WHOIS: %s -> %s", ip, org)

    save_ip_cache(cache)
    return cache


def s3_sync() -> bool:
    result = subprocess.run(
        ["aws", "s3", "sync", f"s3://{S3_BUCKET}/{S3_PREFIX}/",
         str(RAW_DIR) + "/", "--quiet"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        log.error("s3 sync failed: %s", result.stderr.strip())
        return False
    return True


def find_new_files(force: bool) -> list[tuple[Path, Path]]:
    """Return list of (gz_path, ndjson_path) pairs that need processing."""
    pairs = []
    for gz_path in RAW_DIR.rglob("*.json.gz"):
        rel = gz_path.relative_to(RAW_DIR)
        ndjson_path = NDJSON_DIR / rel.with_suffix("").with_suffix(".ndjson")
        if not force and ndjson_path.exists() and ndjson_path.stat().st_mtime > gz_path.stat().st_mtime:
            continue
        pairs.append((gz_path, ndjson_path))
    return pairs


def extract_ips(gz_path: Path) -> set[str]:
    """Extract unique sourceIPAddress values from a CloudTrail .json.gz."""
    ips = set()
    try:
        with gzip.open(gz_path, "rt") as f:
            data = json.load(f)
        for record in data.get("Records", []):
            ip = record.get("sourceIPAddress", "")
            if ip:
                ips.add(ip)
    except Exception as e:
        log.warning("Failed to extract IPs from %s: %s", gz_path, e)
    return ips


def convert_and_enrich(gz_path: Path, ndjson_path: Path, ip_cache: dict[str, str]):
    """Convert .json.gz to enriched NDJSON."""
    ndjson_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = ndjson_path.with_suffix(".tmp")
    try:
        with gzip.open(gz_path, "rt") as f:
            data = json.load(f)
        with open(tmp_path, "w") as out:
            for record in data.get("Records", []):
                ip = record.get("sourceIPAddress", "")
                record["sourceIPOrg"] = ip_cache.get(ip, ip)
                out.write(json.dumps(record, separators=(",", ":")) + "\n")
        tmp_path.rename(ndjson_path)
    except Exception as e:
        log.warning("Failed to process %s: %s", gz_path.relative_to(RAW_DIR), e)
        tmp_path.unlink(missing_ok=True)


def prune_old_files(directory: Path, max_age_days: int = 31):
    """Remove files older than max_age_days and empty directories."""
    cutoff = time.time() - (max_age_days * 86400)
    for path in directory.rglob("*"):
        if path.is_file() and path.stat().st_mtime < cutoff:
            path.unlink()
    # Clean empty dirs bottom-up
    for path in sorted(directory.rglob("*"), reverse=True):
        if path.is_dir() and not any(path.iterdir()):
            path.rmdir()


def main():
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    NDJSON_DIR.mkdir(parents=True, exist_ok=True)

    ip_cache = load_ip_cache()
    log.info("Starting: s3://%s/%s/ -> %s (interval: %ds, cached IPs: %d)",
             S3_BUCKET, S3_PREFIX, RAW_DIR, SYNC_INTERVAL, len(ip_cache))

    while True:
        log.info("Syncing from s3://%s/%s/", S3_BUCKET, S3_PREFIX)
        if not s3_sync():
            time.sleep(SYNC_INTERVAL)
            continue

        force = not ENRICHED_SENTINEL.exists()
        pairs = find_new_files(force)

        if pairs:
            log.info("Processing %d files...", len(pairs))

            # Collect all unique IPs from new files
            all_ips: set[str] = set()
            for gz_path, _ in pairs:
                all_ips.update(extract_ips(gz_path))

            # Resolve uncached IPs
            ip_cache = resolve_ips(all_ips, ip_cache)

            # Convert and enrich
            for gz_path, ndjson_path in pairs:
                convert_and_enrich(gz_path, ndjson_path, ip_cache)

            ENRICHED_SENTINEL.touch()

        prune_old_files(RAW_DIR)
        prune_old_files(NDJSON_DIR)

        ndjson_count = sum(1 for _ in NDJSON_DIR.rglob("*.ndjson"))
        log.info("Sync complete. %d ndjson files, %d cached IPs.",
                 ndjson_count, len(ip_cache))

        time.sleep(SYNC_INTERVAL)


if __name__ == "__main__":
    main()
