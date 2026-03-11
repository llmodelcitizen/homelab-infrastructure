# Tailscale

Installs [Tailscale](https://tailscale.com) on both vps and myserver, creating a private mesh network between them. Prometheus on myserver already scrapes a local node-exporter for host metrics; Tailscale extends this to the VPS, letting Prometheus scrape its node-exporter over an encrypted link without exposing port 9100 to the public internet.

The existing WireGuard tunnel isn't reused here because it's dedicated to qBittorrent. Gluetun owns that interface and routes torrent traffic through it. Adding metrics scraping would require extra routes through Gluetun's network namespace or a second WireGuard tunnel. Tailscale is simpler: full mesh connectivity with no routing hacks.

### Prerequisites

1. Create a **reusable** auth key in the [Tailscale admin console](https://login.tailscale.com/admin/settings/keys) (expires after first use is fine; it's only needed during initial `tailscale up`)
2. Create an **API access token** in the Tailscale admin console (Settings > Keys > Generate access token) — needed for ACL management
3. Store both in Vault:
   ```bash
   vault kv put secret/tailscale authkey=tskey-auth-... apikey=tskey-api-...
   ```

### Run from myserver

```bash
# Install Tailscale and connect both hosts
ansible-playbook tailscale/tailscale.yml

# Apply ACL policy (only myserver -> vps:9100 allowed)
ansible-playbook tailscale/tailscale-acl.yml
```

The install playbook prints each host's Tailscale IP at the end. Use the vps IP to fill in the `prometheus.yml` node-exporter target.

## What it deploys

- Adds the Tailscale apt repo and installs `tailscale`
- Enables and starts `tailscaled`
- Authenticates each host with the Vault-stored auth key
- Enables `--shields-up` on myserver (blocks all inbound Tailscale connections since it only needs to initiate outbound scraping)

### tailscale-acl.yml

- Discovers each host's Tailscale hostname and IP automatically
- Applies an ACL policy via the Tailscale API: only myserver -> vps:9100
- All other traffic between tailnet devices is denied
- Verifies the metrics endpoint is still reachable after applying

## Vault secrets

| Path | Key | Description |
|------|-----|-------------|
| `secret/tailscale` | `authkey` | Reusable pre-auth key from Tailscale admin console |
| `secret/tailscale` | `apikey` | API access token for ACL management (Settings > Keys > Generate access token). Only needed when running `tailscale-acl.yml` — a short-lived token is fine since the ACL persists in Tailscale's control plane after it's applied. Generate a new one if the old token has expired. |

## Verify

```bash
# On either host
tailscale status

# From myserver -- confirm vps is reachable
tailscale ping <VPS_TAILSCALE_IP>
```
