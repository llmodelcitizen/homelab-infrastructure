# qBittorrent

## Authentication Bypass

qBittorrent's built-in authentication is bypassed for requests coming through Traefik, since Authelia already handles SSO + 2FA. The init script `01-reverse-proxy.sh` configures this on every container start.

Key settings:

- **Reverse proxy support: disabled.** With it enabled, qBittorrent extracts the real client IP from `X-Forwarded-For` and uses that for auth whitelist checks, which defeats the bypass since the client IP isn't in the Docker subnet. With it disabled, qBittorrent sees Traefik's direct connection IP (`172.18.0.x`), and the whitelist works. Traefik and Authelia already log real client IPs, so nothing is lost.
- **Auth subnet whitelist:** `172.18.0.0/16` (traefik-public network). Bypasses qBittorrent login for requests arriving from Traefik.

Note: Radarr (and future Sonarr) connect to qBittorrent over the default arr bridge network, not `traefik-public`, so they still authenticate with qBittorrent's username/password. This is expected; the bypass only applies to the web UI accessed through Traefik.
