# WireGuard Server

Sets up a WireGuard VPN server on your cheap VPS node with unlimited bandwidth so that qBittorrent traffic is routed through that network. This is made possible via a sidecar container called Gluetun. The setup includes NAT masquerading, BitTorrent port forwarding (arbitrary 6881 in this case), and stores client credentials in Vault. See [services/arr](../../services/arr/) for the Gluetun and qBittorrent container configuration.

**Architecture:**

```
Internet <-> vps (WireGuard server, NAT, DNAT :6881)
                  ^
                  | WireGuard tunnel
                  v
             Gluetun (WireGuard client, container on myserver)
                  ^
                  | shared network namespace
                  v
             qBittorrent
```

### Run from myserver

```bash
ansible-playbook wg-torrent/wireguard-server.yml
```

### Regenerate all WireGuard keys (server + client):

```bash
ansible-playbook wg-torrent/wireguard-server.yml -e regenerate_keys=true
```

## Vault secret

The playbook writes client credentials to `secret/wireguard`:

| Key | Description |
|-----|-------------|
| `client_private_key` | WireGuard client private key |
| `server_public_key` | WireGuard server public key |
| `endpoint` | vps public IP |
| `endpoint_port` | `51820` |
| `client_address` | `10.10.0.2/32` |

## Verify port forwarding

```bash
# From vps: test that 6881 reaches qBittorrent through the tunnel
ssh -i ~/.ssh/vps -p 2222 myuser@vps "nc -zv -w5 10.10.0.2 6881"

# From myserver: test the full DNAT path (internet -> vps -> tunnel -> qbittorrent)
docker exec radarr nc -zv -w5 vps 6881

# Confirm traffic exits through vps's IP
docker exec gluetun wget -qO- http://1.1.1.1/cdn-cgi/trace | grep ip=
```

## Troubleshooting

```bash
# Check WireGuard status on vps
ssh -i ~/.ssh/vps -p 2222 myuser@vps sudo wg show

# Verify Vault credentials
vault kv get secret/wireguard

# Check Gluetun tunnel on myserver
docker logs gluetun
docker exec gluetun wget -qO- https://ifconfig.me

# Test qBittorrent reachability from radarr
docker exec radarr wget -qO- http://gluetun:8080/api/v2/app/version
```
