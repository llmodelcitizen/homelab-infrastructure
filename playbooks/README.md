# Ansible Playbooks

Most playbooks run locally; some can or must run remotely. See each directory's README for examples.

## Prerequisites

1. **Ansible:**
   ```bash
   sudo apt install ansible
   ```

2. **Python dependencies:**
   ```bash
   sudo apt install python3-boto3 python3-botocore
   ```

3. **Ansible collections:**
   ```bash
   ansible-galaxy collection install -r requirements.yml
   ```

4. **AWS session active** (only for playbooks marked with `AWS` below):
   ```bash
   aws sso login
   ```

## Playbooks

When setting up a new server, run playbooks 1–8 in order before starting [services](../services/).

| # | Playbook README | Description | Requires AWS |
|:-:|----------|-------------|:---:|
| 1 | [nvidia/nvidia.yml](nvidia/) | NVIDIA GPU driver, DKMS, and container toolkit setup for frigate + plex | No |
| 2 | [email/email-setup.yml](email/) | Email sending via SMTP or HTTPS relay (used by vault-auto-unseal) | Yes |
| 3 | [unattended_upgrades/unattended-upgrades.yml](unattended_upgrades/) | Automatic security updates with reboot scheduling | No |
| 4 | [vault_auto_unseal/vault-auto-unseal.yml](vault_auto_unseal/) | Automatically unseal Vault at boot before Docker starts | No |
| 5 | [vault_mirror/vault-mirror.yml](vault_mirror/) | Mirror AWS Secrets Manager credentials to Vault | Yes |
| 6 | [wg-torrent/wireguard-server.yml](wg-torrent/) | WireGuard VPN server on vps for qBittorrent tunneling → secret/wireguard | No |
| 7 | [tailscale/tailscale.yml](tailscale/) | Tailscale mesh VPN between vps and myserver for remote VPS metrics scraping | No |
| 7a | [tailscale/tailscale-acl.yml](tailscale/) | Restrict tailnet traffic to only myserver → vps:9100 via Tailscale API | No |
| 8 | [node-exporter/node-exporter.yml](node-exporter/) | Prometheus node-exporter on vps, bound to Tailscale IP only | No |
| - | [backup/deploy-backup.yml](backup/) | Daily rsync backups to NAS with Vault credentials and email alerts | No |
| - | [companion-satellite/companion-satellite.yml](companion-satellite/) | Provision Raspberry Pis as Bitfocus Companion Satellite appliances | No |

## Inventory

Hosts are defined in `../hosts.ini`:

| Group | Hosts | Notes |
|-------|-------|-------|
| myserver | 192.0.2.10 | For most of the stuff in this repo |
| boxes | box1, box2, box3 | How many raspberry Pi do you actually have |
| vps | 123.123.123.123 | `use_email_relay=true` (if 587 is blocked) |
