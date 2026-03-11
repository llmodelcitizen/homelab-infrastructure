# Traefik Global Reverse Proxy

This directory contains the global Traefik instance that provides HTTPS termination for multiple services (forgejo, frigate, companion).

Create the directory for Let's Encrypt certificates:
```bash
sudo mkdir -p /opt/traefik/acme
sudo chown $USER:$USER /opt/traefik/acme
```

Traefik must start first. All other services join the `traefik-public` network it creates. See [../README.md](../README.md) for full startup order.

```bash
./traefikctl up -d
```

The `traefikctl` script reads config from `../../vars.yml` and fetches Route53 credentials from Vault (`secret/traefik`).

## Dashboard

The Traefik dashboard is available at https://traefik.example.com, protected by Authelia with 2FA.

The dashboard shows:
- Active routers and their rules
- Services and their health status
- Middlewares (including authelia)
- TLS certificates

## Troubleshooting

**Check traefik logs:**
```bash
./traefikctl logs -f traefik
```

**Verify network connectivity:**
```bash
docker network inspect traefik-public
```

**Verify TLS certificate:**
```bash
openssl s_client -connect auth.example.com:443 -servername auth.example.com </dev/null 2>/dev/null | openssl x509 -noout -dates
```

**Check certificate status:**
```bash
./traefikctl exec traefik cat /acme/acme.json | jq '.letsencrypt.Certificates[].domain'
```
