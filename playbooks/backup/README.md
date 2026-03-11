# Backup Service

Python-based backup service that syncs configured directories to your NAS via rsync daemon protocol. Runs as a systemd timer, retrieves credentials from HashiCorp Vault, and sends email notifications on failure.

Uses `--delete` to mirror source directories exactly. Files removed from the source will also be removed from the destination.

## Configuration

| Setting | Value |
|---------|-------|
| NAS hostname | `nas.local` |
| NAS user | `myuser` |
| Vault path | `secret/backupservice/rsync` (KV v2) |
| Vault key | `password` |

Backup sources are defined in `backup_sources.yml` with per-source share configuration.

## Prerequisites

- HashiCorp Vault running locally with token at `/root/.vault-token`
- msmtp configured for email notifications (from [email playbook](../email/))
- rsync daemon enabled on your NAS with appropriate module configured

Store the rsync password in Vault:
```bash
vault kv put secret/backupservice/rsync password='your-rsync-password'
```

## Deployment

```bash
ansible-playbook backup/deploy-backup.yml
```

Local:

```bash
ansible-playbook backup/deploy-backup.yml -c local
```

## Installed Files

| Path | Description |
|------|-------------|
| `/opt/backupservice/backup.py` | Main Python script |
| `/opt/backupservice/config.yml` | Host-specific configuration |
| `/etc/systemd/system/backup.service` | systemd service unit |
| `/etc/systemd/system/backup.timer` | systemd timer (daily 2 AM) |
| `/etc/logrotate.d/backup` | Log rotation config |
| `/var/log/backup/` | Log directory |

## Usage

### Manual Operations

```bash
# Test Vault access
vault kv get secret/backupservice/rsync

# Dry run (no changes)
sudo /opt/backupservice/backup.py --dry-run --verbose

# Manual backup run
sudo systemctl start backup.service

# Check timer status
systemctl status backup.timer

# View logs
sudo journalctl -u backup.service
sudo cat /var/log/backup/backup.log

# List upcoming timers
systemctl list-timers backup.timer
```

### Script Options

```bash
sudo /opt/backupservice/backup.py [options]

Options:
  --config PATH    Path to configuration file (default: /opt/backupservice/config.yml)
  --dry-run        Perform a trial run with no changes made
  --verbose, -v    Enable verbose output
```

## Schedule

The backup runs daily at 2:00 AM with up to 15 minutes random delay. This is scheduled before the 3:00 AM automatic reboot window configured by unattended-upgrades.

If the system was powered off during the scheduled time, the backup will run on next boot (`Persistent=true`).

## Backup Sources

See `backup_sources.yml` for current configuration. Each source specifies its target shared folder on the NAS.

Sources are processed sequentially in order. Place more important/smaller backups first so they complete even if later backups timeout or fail.

## Notifications

- **On failure**: Email sent via `/usr/local/bin/send-mail` (requires msmtp configured)
- **On success**: Email sent (configurable in config template)
- **On cancellation**: Email sent when service is stopped, indicating which source was being processed

## Customization

Edit `backup_sources.yml` to add or modify backup sources:

```yaml
backup_sources:
  - path: /home/myuser/somedirectory
    name: home-somedirectory
    share: myserver            # required - the shared folder on your NAS
    backup_root: backups       # optional - subdirectory within this share
    excludes:                  # optional - patterns to exclude
      - ".cache"
      - "node_modules"
  - path: /mnt/ssd/frigate
    name: frigate
    share: nvr                 # a different shared folder, and no backup_root
```

### Destination Path Structure

| Field | Required | Description |
|-------|----------|-------------|
| `path` | yes | Local source directory |
| `name` | yes | Name used in destination path |
| `share` | yes | Shared folder name on your NAS |
| `backup_root` | no | Subdirectory within share (default: none) |
| `excludes` | no | List of rsync exclude patterns |

Resulting destination URLs:
- With `backup_root`: `rsync://user@host/<share>/<backup_root>/<hostname>/<name>`
- Without `backup_root`: `rsync://user@host/<share>/<hostname>/<name>`

## Troubleshooting

### Vault Issues

```bash
# Check Vault status
vault status

# Verify token exists
sudo ls -la /root/.vault-token

# Test secret retrieval
vault kv get secret/backupservice/rsync
```

### rsync Issues

```bash
# List available rsync modules on the NAS
rsync rsync://myuser@nas.local/

# Test rsync daemon connectivity (dry-run)
RSYNC_PASSWORD='password' rsync -rltvz --dry-run /etc/hostname rsync://myuser@nas.local/myserver/backups/test/
```

### Email Issues

```bash
# Test send-mail script
/usr/local/bin/send-mail "Test Subject" "Test body"

# Check msmtp configuration
sudo cat /etc/msmtprc
```

## Error Handling

| Error | Response |
|-------|----------|
| Vault unreachable | Log error, send email, exit 1 |
| NAS unreachable | Log error, send email, exit 1 |
| rsync failure | Log error, continue with other sources, email summary |
| Timeout (8h) | Process killed by systemd |
