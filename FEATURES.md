# Features

## Networking & Access

| Feature | Description |
|---------|-------------|
| HTTPS reverse proxy | Terminates TLS for all services via [Let's Encrypt DNS-01](services/traefik/README.md) challenge through Route53, with automatic certificate renewal. Creates the `traefik-public` Docker network that all other services join. |
| Single sign-on with 2FA | Protects web services through [Authelia](services/authelia/README.md) forward-auth with TOTP and WebAuthn/YubiKey support, backed by Redis sessions. Config is generated at startup from Vault-injected secrets. |
| DNS management | Provisions and maintains [Route53](terraform/README.md) records for all service subdomains via Terraform. |
| Private metrics mesh | Extends Prometheus scraping to the VPS over a [Tailscale](playbooks/tailscale/README.md) mesh with shields-up on myserver, ACLs restricting traffic to port 9100 only, and VPS [node-exporter](playbooks/node-exporter/README.md) bound to the Tailscale IP. Local myserver metrics are scraped directly via Docker networking. |
| VPN-tunneled downloads | Routes BitTorrent traffic through a [WireGuard](playbooks/wg-torrent/README.md) tunnel to an Ansible-provisioned VPS via [Gluetun](services/arr/README.md), with NAT masquerading, inbound port forwarding, and a kill switch that prevents any traffic if the tunnel drops. |

## Applications

| Feature | Description |
|---------|-------------|
| Self-hosted Git forge | Hosts private Git repositories via [Forgejo](services/forge/README.md) with PostgreSQL storage for code, issues, and pull requests, with SMTP email notifications via SES. |
| NVR with hardware acceleration | Records and detects objects on camera feeds using NVIDIA GPU hardware decoding, TensorRT inference, and NVENC encoding via the [NVIDIA Container Toolkit](playbooks/nvidia/README.md) runtime, alongside a Coral USB TPU, with go2RTC streaming. |
| Media server with GPU transcoding | Serves a [Plex](services/arr/README.md) library with NVIDIA NVENC/NVDEC hardware transcoding via the Container Toolkit runtime, and automated metadata enrichment via [Kometa](services/arr/README.md). |
| Automated media management | Manages movie acquisition through [Radarr](services/arr/README.md) and [Prowlarr](services/arr/README.md), with [Byparr](services/arr/README.md) providing Cloudflare bypass for protected indexers. The arr stack enforces startup ordering to prevent race conditions, and select services bypass Authelia forward-auth for API compatibility. |
| Stream Deck automation | Controls home automation and other systems through [Bitfocus Companion](services/companion-server/README.md), with satellite support for USB Stream Deck devices. |

## Observability

| Feature | Description |
|---------|-------------|
| Metrics and alerting | Collects host and container metrics with [Prometheus](services/monitoring/README.md), retaining 120 days / 20 GB, with email alerts for disk and CPU thresholds via [Alertmanager](services/monitoring/README.md) and SES. |
| Log aggregation | Ships Docker and system logs to [Loki](services/monitoring/README.md) via [Promtail](services/monitoring/README.md) for centralized search. |
| Pre-built dashboards | Provisions seven [Grafana](services/monitoring/README.md) dashboards covering host metrics, containers, logs, Frigate, Traefik, CloudTrail, and image updates. |
| AWS activity monitoring | Logs IAM API calls via multi-region [CloudTrail](terraform/README.md), syncs to [Loki](services/monitoring/README.md) with WHOIS enrichment, and sends real-time alerts on sensitive operations. |
| Image update tracking | Monitors running containers for new upstream releases and sends daily notifications via [Diun](services/monitoring/README.md). |
| Alert and query validation | [`test-alert.sh`](services/monitoring/README.md) fires test alerts through Alertmanager to verify the notification pipeline, and [`validate-dashboard-queries.py`](services/monitoring/README.md) checks all Grafana dashboard queries for correctness. |

## Infrastructure & Ops

| Feature | Description |
|---------|-------------|
| AWS Secrets Manager and downstream flow | Provisions three sets of AWS credentials (SMTP, Route53, CloudTrail sync) via [Terraform](terraform/README.md) and stores them in AWS Secrets Manager. The [`vault_mirror`](playbooks/vault_mirror/README.md) playbook mirrors them one-way into HashiCorp Vault, after which services operate without AWS authentication or internet connectivity. The [`email`](playbooks/email/README.md) playbook is the only consumer that reads from Secrets Manager directly, requiring an active AWS session. |
| Vault secret injection | Injects secrets from [HashiCorp Vault](playbooks/vault_mirror/README.md) into containers at startup through unified `*ctl` wrapper scripts, which abort immediately if Vault is sealed or unauthenticated. Vault holds both the AWS-mirrored credentials above and Vault-native secrets (application keys, VPN credentials, API tokens) that are created directly in Vault without AWS involvement. Vault consumers include [`arrctl`](services/arr/README.md), [`autheliactl`](services/authelia/README.md), [`forgectl`](services/forge/README.md), [`monitoringctl`](services/monitoring/README.md), [`traefikctl`](services/traefik/README.md), [`vpn-health-check.sh`](services/arr/README.md), [`backup.py`](playbooks/backup/README.md), [`tailscale.yml`](playbooks/tailscale/README.md), [`tailscale-acl.yml`](playbooks/tailscale/README.md).|
| Vault auto-unseal at boot | Unseals Vault before Docker starts using [age-encrypted keys](playbooks/vault_auto_unseal/README.md) and systemd service ordering, with email alerts on failure. |
| HTTPS email relay | Sends email from VPS and other SMTP-blocked hosts through an [API Gateway + Lambda relay](playbooks/email/README.md), with drop-in `mail` command replacement. |
| Automated backups | Syncs service data to a NAS daily via [rsync](playbooks/backup/README.md) with Vault-sourced credentials, systemd scheduling, and email notifications. |
| Unattended security upgrades | Applies [security patches](playbooks/unattended_upgrades/README.md) automatically across all hosts with email notifications and scheduled reboots. |
| NVIDIA driver lifecycle | Installs GPU drivers and the Container Toolkit via [DKMS](playbooks/nvidia/README.md), surviving unattended kernel upgrades. |
| Service updater | Discovers services dynamically via `update.py` across all `*ctl` scripts with parallel image pulls, custom image rebuilds, and a Rich terminal UI. `vault-login` provides interactive Vault authentication. |
