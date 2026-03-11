# Services

Each service is a Docker Compose stack managed through a `*ctl` wrapper script that sources shared config from `vars.yml` and injects secrets from HashiCorp Vault at startup.

## Prerequisites

### 1. Docker

Install [Docker Engine](https://docs.docker.com/engine/install/) with the [Compose plugin](https://docs.docker.com/compose/install/). All services run as Docker Compose stacks.

### 2. Terraform

Terraform provides supporting AWS infrastructure (DNS, TLS certificates, IAM users, Secrets Manager, email delivery, CloudTrail monitoring, etc.). Once provisioned, services have no runtime dependency on AWS. See [terraform/README.md](../terraform/README.md).

### 3. Playbooks

Run the Ansible playbooks before starting services. See [playbooks/README.md](../playbooks/README.md) for the required run order.

## Untracked Configuration

These sensitive config files are git-ignored and must be created manually:

| File | Service | Description |
|------|---------|-------------|
| `frigate/config.yml` | Frigate | Camera streams, detectors, recording config -- see [frigate/README.md](frigate/README.md) |
| `authelia/users_database.yml` | Authelia | Local user database -- see [authelia/README.md](authelia/README.md) |

## Services

Start services in the order listed. Traefik must come first (it creates the `traefik-public` network used by all other services) and Authelia second (it provides the SSO middleware referenced by most services). The remaining services can be started in any order.

All runtime secrets live in the server's local HashiCorp Vault. The `vault_mirror` and `wg-torrent` playbooks populate `secret/smtp`, `secret/traefik`, `secret/cloudtrail-sync`, and `secret/wireguard`. The remaining secrets are created during individual service setup. See each service's README for details.

| Order | Service | Description | Vault Secrets | Details |
|:-----:|---------|-------------|---------------|---------|
| 1 | [traefik](traefik/) | Reverse proxy, Let's Encrypt HTTPS via DNS-01 | `secret/traefik` | Creates `traefik-public` network |
| 2 | [authelia](authelia/) | SSO + 2FA forward-auth for Traefik | `secret/authelia`, `secret/smtp` | Redis session backend |
| 3 | [forge](forge/) | Forgejo Git server + PostgreSQL | `secret/forge` | Bypasses Authelia (own auth) |
| 4 | [frigate](frigate/) | NVR with NVIDIA GPU + Coral TPU | - | RTSP :8554, WebRTC :8555 |
| 5 | [companion-server](companion-server/) | Bitfocus Companion server | - | Satellite :16622-16623 |
| 6 | [monitoring](monitoring/) | Grafana, Prometheus, Alertmanager, Loki, Promtail, Node Exporter, cAdvisor, CloudTrail sync, Diun | `secret/smtp`, `secret/cloudtrail-sync` | 30-day retention, email alerts via SES, daily image update notifications |
| 7 | [arr](arr/) | Plex, qBittorrent, Radarr, Prowlarr, Kometa, Byparr, Gluetun VPN | `secret/wireguard`, `secret/kometa` | BitTorrent :6881, Plex :32400 |

## ctl Wrappers

Each service has a `*ctl` script (e.g. `traefikctl`, `arrctl`) that wraps `docker compose`. This helper reads shared config from `../../vars.yml`, fetches secrets from HashiCorp Vault, exports them as environment variables, then passes all arguments through to `docker compose`. Any `docker compose` command works:

```bash
./traefikctl up -d
./traefikctl logs -f
./traefikctl down
./traefikctl pull && ./traefikctl up -d
```

To update services (pull images, rebuild custom builds, recreate changed containers):

```bash
./update.py all              # update all services
./update.py arr monitoring   # update specific services
```

Vault must be unsealed before running ctl commands for services that use Vault secrets. Each ctl script authenticates automatically by decrypting the age-encrypted Vault token via `sudo`, so no manual `vault-login` is needed. The token exists only as an in-process environment variable and is never written to disk. See the [vault auto unseal playbook README](../playbooks/vault_auto_unseal/) for more information.

## Routing

| Domain | Service | Internal Port | Auth |
|--------|---------|---------------|------|
| traefik.example.com | dashboard | api@internal | SSO + 2FA |
| auth.example.com | authelia | 9091 | SSO portal |
| forge.example.com | forgejo | 4000 | bypass (own auth) |
| frigate.example.com | frigate | 5000 | SSO + 2FA |
| companion.example.com | companion | 8000 | SSO + 2FA |
| grafana.example.com | grafana | 3000 | SSO + 2FA |
| prometheus.example.com | prometheus | 9090 | SSO + 2FA |
| alertmanager.example.com | alertmanager | 9093 | SSO + 2FA |
| cadvisor.example.com | cadvisor | 8080 | SSO + 2FA |
| qbit.example.com | qbittorrent | 8080 | SSO + 2FA |
| radarr.example.com | radarr | 7878 | SSO + 2FA |
| prowlarr.example.com | prowlarr | 9696 | SSO + 2FA |
| plex.example.com | plex | redirect → :32400 | (redirect only) |
