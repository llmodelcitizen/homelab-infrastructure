#!/usr/bin/env python3
"""
Backup script that syncs configured directories to a NAS via rsync daemon.
Retrieves credentials from HashiCorp Vault and sends email notifications.
"""

import argparse
import json
import logging
import os
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import yaml

# Global state for signal handler
_signal_context = {
    "hostname": None,
    "notifications": None,
    "logger": None,
    "current_source": None,
}


def format_duration(seconds: float) -> str:
    """Format elapsed seconds as e.g. '1h 23m 45s' or '2m 12s'."""
    total = int(seconds)
    h, remainder = divmod(total, 3600)
    m, s = divmod(remainder, 60)
    if h:
        return f"{h}h {m:02d}m {s:02d}s"
    if m:
        return f"{m}m {s:02d}s"
    return f"{s}s"


def setup_logging(verbose: bool, log_file: str | None = None) -> logging.Logger:
    """Configure logging to both file and stdout."""
    logger = logging.getLogger("backup")
    logger.setLevel(logging.DEBUG if verbose else logging.INFO)

    formatter = logging.Formatter(
        "%(asctime)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Console handler (captured by journald when run as service)
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    # File handler
    if log_file:
        log_path = Path(log_file)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        file_handler = logging.FileHandler(log_file)
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)

    return logger


def load_config(config_path: str) -> dict:
    """Load configuration from YAML file."""
    with open(config_path) as f:
        return yaml.safe_load(f)


def get_vault_secret(vault_addr: str, secret_path: str, secret_key: str, logger: logging.Logger) -> str:
    """Retrieve secret from HashiCorp Vault using CLI (KV v2)."""
    logger.debug(f"Retrieving secret from Vault: {secret_path}")

    env = os.environ.copy()
    env["VAULT_ADDR"] = vault_addr

    try:
        result = subprocess.run(
            ["vault", "kv", "get", "-format=json", secret_path],
            capture_output=True,
            text=True,
            env=env,
            check=True,
        )
        data = json.loads(result.stdout)
        secret_value = data["data"]["data"][secret_key]
        logger.debug("Successfully retrieved secret from Vault")
        return secret_value
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to retrieve secret from Vault: {e.stderr}")
        raise
    except (json.JSONDecodeError, KeyError) as e:
        logger.error(f"Failed to parse Vault response: {e}")
        raise


def send_notification(subject: str, body: str, recipient: str, logger: logging.Logger) -> bool:
    """Send email notification using the existing send-mail script."""
    send_mail_path = "/usr/local/bin/send-mail"

    if not Path(send_mail_path).exists():
        logger.warning(f"send-mail script not found at {send_mail_path}, skipping notification")
        return False

    try:
        subprocess.run(
            [send_mail_path, subject, body],
            check=True,
            capture_output=True,
            text=True,
        )
        logger.info(f"Notification sent: {subject}")
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to send notification: {e.stderr}")
        return False


def handle_termination(signum, frame):
    """Handle SIGTERM/SIGINT by sending cancellation notification."""
    ctx = _signal_context
    if ctx["logger"]:
        ctx["logger"].warning(f"Received signal {signum}, backup cancelled")

    if ctx["notifications"] and ctx["notifications"].get("email_on_failure") and ctx["hostname"]:
        current = ctx["current_source"] or "unknown"
        send_notification(
            f"[{ctx['hostname']}] Backup CANCELLED",
            f"Backup was cancelled (signal {signum}) while processing: {current}",
            ctx["notifications"].get("recipient", "root"),
            ctx["logger"],
        )

    sys.exit(128 + signum)


def run_rsync(
    source: str,
    destination: str,
    password: str,
    excludes: list[str] | None,
    dry_run: bool,
    logger: logging.Logger,
) -> tuple[bool, str]:
    """Execute rsync using daemon protocol with RSYNC_PASSWORD."""
    rsync_cmd = [
        "rsync",
        "-rltvz",
        "--delete",
        "--stats",
    ]

    if dry_run:
        rsync_cmd.append("--dry-run")

    if excludes:
        for exclude in excludes:
            rsync_cmd.extend(["--exclude", exclude])

    # Ensure source ends with / to sync contents
    if not source.endswith("/"):
        source = source + "/"

    rsync_cmd.extend([source, destination])

    env = os.environ.copy()
    env["RSYNC_PASSWORD"] = password

    logger.debug(f"Running: {' '.join(rsync_cmd)}")

    try:
        result = subprocess.run(
            rsync_cmd,
            capture_output=True,
            text=True,
            env=env,
            timeout=28800,  # 8-hour timeout
        )

        if result.returncode == 0:
            logger.info(f"rsync completed successfully for {source}")
            return True, result.stdout
        else:
            logger.error(f"rsync failed for {source}: {result.stderr}")
            return False, result.stderr

    except subprocess.TimeoutExpired:
        logger.error(f"rsync timed out for {source}")
        return False, "Timeout after 8 hours"
    except Exception as e:
        logger.error(f"rsync error for {source}: {e}")
        return False, str(e)


def main():
    parser = argparse.ArgumentParser(description="Backup directories to NAS via rsync")
    parser.add_argument(
        "--config",
        default="/opt/backupservice/config.yml",
        help="Path to configuration file",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Perform a trial run with no changes made",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable verbose output",
    )
    args = parser.parse_args()

    # Load configuration
    try:
        config = load_config(args.config)
    except Exception as e:
        print(f"Failed to load configuration: {e}", file=sys.stderr)
        sys.exit(1)

    # Setup logging
    log_file = config.get("log_file", "/var/log/backup/backup.log")
    logger = setup_logging(args.verbose, log_file)

    logger.info("=" * 60)
    logger.info(f"Backup started at {datetime.now().isoformat()}")
    if args.dry_run:
        logger.info("DRY RUN MODE - no changes will be made")

    # Validate required config sections
    for key in ("nas", "vault"):
        if key not in config:
            logger.error(f"Missing required config section: {key}")
            sys.exit(1)

    nas = config["nas"]
    vault = config["vault"]

    for key in ("hostname", "user"):
        if key not in nas:
            logger.error(f"Missing required nas config: {key}")
            sys.exit(1)

    for key in ("addr", "secret_path", "secret_key"):
        if key not in vault:
            logger.error(f"Missing required vault config: {key}")
            sys.exit(1)

    notifications = config.get("notifications", {})

    hostname = os.uname().nodename
    failures = []
    successes = []

    # Setup signal handler for graceful cancellation
    _signal_context["hostname"] = hostname
    _signal_context["notifications"] = notifications
    _signal_context["logger"] = logger
    signal.signal(signal.SIGTERM, handle_termination)
    signal.signal(signal.SIGINT, handle_termination)

    # Retrieve password from Vault
    try:
        password = get_vault_secret(
            vault["addr"],
            vault["secret_path"],
            vault["secret_key"],
            logger,
        )
    except Exception as e:
        error_msg = f"Failed to retrieve credentials from Vault: {e}"
        logger.error(error_msg)
        if notifications.get("email_on_failure"):
            send_notification(
                f"[{hostname}] Backup FAILED - Vault Error",
                error_msg,
                notifications.get("recipient", "root"),
                logger,
            )
        sys.exit(1)

    # Process each backup source
    job_start = time.monotonic()
    for source in config.get("backup_sources", []):
        source_path = source["path"]
        source_name = source.get("name", Path(source_path).name)
        _signal_context["current_source"] = source_name
        excludes = source.get("excludes", [])

        if not Path(source_path).exists():
            logger.warning(f"Source path does not exist: {source_path}, skipping")
            failures.append((source_name, "Source path does not exist", 0.0))
            continue

        # share is required, backup_root is optional
        if "share" not in source:
            logger.error(f"Source {source_name} missing required 'share' field, skipping")
            failures.append((source_name, "Missing required 'share' field", 0.0))
            continue
        share = source["share"]
        backup_root = source.get("backup_root", "")

        # Build destination path (rsync daemon URL format)
        # Always includes hostname; backup_root is optional prefix within share
        if backup_root:
            destination = (
                f"rsync://{nas['user']}@{nas['hostname']}"
                f"/{share}/{backup_root}/{hostname}/{source_name}"
            )
        else:
            destination = (
                f"rsync://{nas['user']}@{nas['hostname']}"
                f"/{share}/{hostname}/{source_name}"
            )

        logger.info(f"Backing up {source_path} -> {destination}")

        source_start = time.monotonic()
        success, output = run_rsync(
            source_path,
            destination,
            password,
            excludes,
            args.dry_run,
            logger,
        )
        elapsed = time.monotonic() - source_start

        if success:
            successes.append((source_name, elapsed))
        else:
            failures.append((source_name, output, elapsed))

    # Summary
    total_elapsed = time.monotonic() - job_start
    logger.info("-" * 60)
    logger.info(f"Backup completed: {len(successes)} succeeded, {len(failures)} failed")
    for name, elapsed in successes:
        logger.info(f"  - {name}: {format_duration(elapsed)}")
    for name, _error, elapsed in failures:
        logger.info(f"  - {name}: {format_duration(elapsed)} (FAILED)")
    logger.info(f"Total time: {format_duration(total_elapsed)}")

    if failures:
        logger.error("Failed backups:")
        for name, error, _elapsed in failures:
            logger.error(f"  - {name}: {error[:100]}...")

        if notifications.get("email_on_failure"):
            failure_details = "\n".join([f"- {name}: {error[:200]}" for name, error, _elapsed in failures])
            success_names = [name for name, _elapsed in successes]
            timing_lines = (
                [f"- {name}: {format_duration(elapsed)}" for name, elapsed in successes]
                + [f"- {name}: {format_duration(elapsed)} (FAILED)" for name, _error, elapsed in failures]
            )
            timing_block = "\n".join(timing_lines)
            body = (
                f"The following backup sources failed:\n\n{failure_details}\n\n"
                f"Successful: {', '.join(success_names) if success_names else 'none'}\n\n"
                f"Time spent:\n{timing_block}\n"
                f"Total: {format_duration(total_elapsed)}"
            )
            # Truncate body to avoid "Argument list too long" error
            if len(body) > 4000:
                body = body[:4000] + "\n\n[truncated]"
            dry_run_label = " (DRY RUN)" if args.dry_run else ""
            send_notification(
                f"[{hostname}] Backup FAILED{dry_run_label} - {len(failures)} source(s)",
                body,
                notifications.get("recipient", "root"),
                logger,
            )
        sys.exit(1)

    if notifications.get("email_on_success"):
        dry_run_label = " (DRY RUN)" if args.dry_run else ""
        success_names = [name for name, _elapsed in successes]
        timing_lines = [f"- {name}: {format_duration(elapsed)}" for name, elapsed in successes]
        timing_block = "\n".join(timing_lines)
        send_notification(
            f"[{hostname}] Backup completed successfully{dry_run_label}",
            f"All {len(successes)} backup sources completed successfully:\n"
            f"{', '.join(success_names)}\n\n"
            f"Time spent:\n{timing_block}\n"
            f"Total: {format_duration(total_elapsed)}",
            notifications.get("recipient", "root"),
            logger,
        )

    logger.info("Backup finished successfully")
    sys.exit(0)


if __name__ == "__main__":
    main()
