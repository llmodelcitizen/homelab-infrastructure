# Node Exporter

Installs [Prometheus node-exporter](https://github.com/prometheus/node_exporter) on the vps as a native systemd service (no Docker). Metrics are bound to the Tailscale IP so port 9100 is never public. Collectors match the node-exporter instance running in Docker on myserver, plus conntrack for NAT monitoring. Together, Prometheus scrapes both: myserver locally via `host.docker.internal:9100` and the VPS remotely over Tailscale.

### Prerequisites

- Tailscale must be installed and connected (run [tailscale.yml](../tailscale/) first)

### Run from myserver

```bash
ansible-playbook node-exporter/node-exporter.yml
```

## What it deploys

- Downloads the official node-exporter tarball and installs to `/usr/local/bin`
- Creates a `node_exporter` system user
- Deploys a hardened systemd unit with `ProtectSystem=strict` and `NoNewPrivileges`
- Binds to the Tailscale IP only (not 0.0.0.0) for defense-in-depth
- Opens port 9100 on the `tailscale0` interface via ufw
- Verifies the `/metrics` endpoint is responding

## Verify

```bash
# From vps (uses Tailscale IP since node-exporter no longer binds to localhost)
curl -s http://<VPS_TAILSCALE_IP>:9100/metrics | head

# From myserver -- confirm scraping works over Tailscale
curl -s http://<VPS_TAILSCALE_IP>:9100/metrics | head
```
