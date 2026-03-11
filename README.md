# Homelab Infrastructure

This repository showcases [Eric's](https://github.com/quaintops) custom Terraform, Ansible playbooks, Docker services, and other tools & glue designed to manage parts of his homelab infrastructure. After a substantial documentation effort, it is now made public so others might benefit and learn.

AWS provides the cloud things (DNS, email, monitoring, etc.), but for the most part the services run locally and remain operational without internet or active AWS authentication, even for most management tasks.

Sorry it's not kubernetes. This is a homelab ;)

## Features

See [FEATURES.md](FEATURES.md) for a summary of functionality.

## Configuration

This repository is public and should contain no secrets nor environment-specific values. Sensitive files (`vars.yml`, `hosts.ini`, Authelia, Frigate, Terraform-backend, and backup config) are all gitignored. It is recommended that you build a private config overlay repository that mirrors this directory structure, but to get started, simply duplicate and modify each of the `.example` files you can find.

## Quick Start

1. First, see the [Terraform README](terraform/README.md)
2. Then, run through the [Playbooks README](playbooks/README.md)
3. Finally, stand up each service you'd like as described in the [Services README](services/README.md)

## Repository Structure

The tree below shows both filesystem paths and logical service groupings.

```
├── vars.yml                    # Shared config (Terraform + Ansible + Docker)
├── hosts.ini                   # Ansible inventory
│
├── terraform/                  # AWS infrastructure (see terraform/README.md)
│   ├── main.tf                 # Root module: backend, provider, module calls
│   ├── versions.tf             # Provider version constraints
│   ├── outputs.tf              # Aggregated outputs from all modules
│   ├── tfinit.sh               # Wrapper: terraform init with backend config
│   └── modules/
│       ├── ses/                # SES domain identity, DKIM, IAM user, SMTP credentials
│       ├── email-relay/        # API Gateway + Lambda email relay for SMTP-blocked hosts
│       ├── traefik-aws/        # Route53 A records, IAM user for DNS-01 challenge
│       ├── iam-monitor/        # EventBridge + Lambda IAM activity alerts
│       ├── cloudtrail-sync/    # IAM user for S3 CloudTrail log sync
│       └── cloudtrail/         # Multi-region management event trail
│
├── services/                   # Docker services (see services/README.md)
│   ├── update.py               # Pull and restart services
│   ├── traefik/                # Reverse proxy, Let's Encrypt DNS-01 (traefikctl)
│   ├── authelia/               # SSO + 2FA forward-auth, Redis session backend (autheliactl)
│   ├── forge/                  # Forgejo git server + PostgreSQL (forgectl)
│   ├── frigate/                # NVR with NVIDIA GPU + Coral TPU (frigatectl)
│   ├── companion-server/       # Bitfocus Companion automation (companionctl)
│   ├── monitoring/             # Monitoring stack (monitoringctl)
│   │   ├── grafana             # Dashboards and visualization
│   │   ├── prometheus          # Metrics collection and alerting rules
│   │   ├── alertmanager        # Alert routing and email notifications
│   │   ├── loki                # Log aggregation
│   │   ├── promtail            # Log shipping to Loki
│   │   ├── node-exporter       # Host metrics
│   │   ├── cadvisor            # Container metrics
│   │   ├── cloudtrail-sync     # S3 CloudTrail log sync into Loki
│   │   └── diun                # Docker image update notifications
│   ├── arr/                    # Media stack (arrctl)
│   │   ├── gluetun             # WireGuard VPN tunnel
│   │   ├── qbittorrent         # BitTorrent client (routed through Gluetun)
│   │   ├── radarr              # Movie management
│   │   ├── prowlarr            # Indexer manager
│   │   ├── plex                # Media server (NVIDIA GPU transcoding)
│   │   ├── kometa              # Plex metadata manager
│   │   └── byparr              # Automated arr interaction
│
└── playbooks/                  # Ansible playbooks (see playbooks/README.md)
    ├── vault_mirror/           # Mirror AWS Secrets Manager → HashiCorp Vault
    ├── email/                  # Email sending via SMTP or HTTPS relay
    ├── unattended_upgrades/    # Automatic security updates with reboot scheduling
    ├── wg-torrent/             # WireGuard VPN server on vps
    ├── nvidia/                 # NVIDIA GPU driver + Container Toolkit
    ├── vault_auto_unseal/      # Auto-unseal Vault at boot
    ├── backup/                 # Daily rsync backups to NAS with email alerts
    ├── tailscale/              # Tailscale mesh VPN with shields-up and ACL policy
    ├── node-exporter/          # Prometheus node-exporter on vps (Tailscale-bound)
    └── companion-satellite/    # Companion Satellite on Raspberry Pis
```

## Documentation

- [terraform/README.md](terraform/README.md) - AWS infrastructure, usage, state management
  - [terraform/modules/README.md](terraform/modules/README.md) - Overview of Terraform modules
- [services/README.md](services/README.md) - Docker services, startup order, prerequisites
  - [services/traefik/README.md](services/traefik/README.md) - Reverse proxy and HTTPS termination
  - [services/authelia/README.md](services/authelia/README.md) - SSO + 2FA forward-auth for Traefik
  - [services/forge/README.md](services/forge/README.md) - Forgejo git server + PostgreSQL
  - [services/frigate/README.md](services/frigate/README.md) - NVR with NVIDIA GPU and Coral TPU
  - [services/companion-server/README.md](services/companion-server/README.md) - Bitfocus Companion server
  - [services/monitoring/README.md](services/monitoring/README.md) - Grafana, Prometheus, Loki, Alertmanager
  - [services/arr/README.md](services/arr/README.md) - Plex, qBittorrent, Radarr, Prowlarr, Kometa, Byparr, Gluetun
  - [services/arr/qbittorrent/README.md](services/arr/qbittorrent/README.md) - qBittorrent authentication bypass
- [playbooks/README.md](playbooks/README.md) - Ansible playbooks and device setup
  - [playbooks/vault_mirror/README.md](playbooks/vault_mirror/README.md) - AWS Secrets Manager to Vault sync
  - [playbooks/email/README.md](playbooks/email/README.md) - Email sending via SMTP or HTTPS relay
  - [playbooks/unattended_upgrades/README.md](playbooks/unattended_upgrades/README.md) - Automatic security updates with reboot scheduling
  - [playbooks/wg-torrent/README.md](playbooks/wg-torrent/README.md) - WireGuard VPN server for qBittorrent tunneling
  - [playbooks/nvidia/README.md](playbooks/nvidia/README.md) - NVIDIA GPU driver and Docker runtime
  - [playbooks/vault_auto_unseal/README.md](playbooks/vault_auto_unseal/README.md) - Auto-unseal Vault at boot
  - [playbooks/backup/README.md](playbooks/backup/README.md) - Daily rsync backups to NAS with email alerts
  - [playbooks/tailscale/README.md](playbooks/tailscale/README.md) - Tailscale mesh VPN between vps and myserver
  - [playbooks/node-exporter/README.md](playbooks/node-exporter/README.md) - Prometheus node-exporter on vps
  - [playbooks/companion-satellite/README.md](playbooks/companion-satellite/README.md) - Companion Satellite on Raspberry Pis
