# Arr Stack

Media management services: qBittorrent (download client), Radarr (movie management), Prowlarr (indexer manager), Plex (media server), Kometa (metadata manager), and Byparr (Cloudflare bypass proxy for Prowlarr), with future support for Sonarr, etc.

All services share a common `/opt/arr/data` directory to enable hardlinking between download clients and media managers.

### 1. Create directories
```bash
sudo mkdir -p /opt/arr/qbittorrent/config
sudo mkdir -p /opt/arr/radarr/config
sudo mkdir -p /opt/arr/prowlarr/config
sudo mkdir -p /opt/arr/plex/config
sudo mkdir -p /opt/arr/kometa/config
sudo mkdir -p /opt/arr/data

sudo chown -R 1000:1000 /opt/arr
```

## Usage

```bash
./arrctl up -d
./arrctl logs -f
./arrctl down
```

## Services

| Service | URL | Internal Port | Auth |
|---------|-----|---------------|------|
| qBittorrent | qbit.example.com | 8080 | SSO + 2FA |
| Radarr | radarr.example.com | 7878 | SSO + 2FA |
| Prowlarr | prowlarr.example.com | 9696 | SSO + 2FA (patched build) |
| Plex | plex.example.com:32400 | 32400 | Own auth (plex.tv), host network |
| Byparr | internal only | 8191 | None |
| Kometa | internal only | N/A | None (scheduled task) |
| Gluetun | internal only | 8080 (health) | None (WireGuard VPN tunnel for qBittorrent) |

**Ports:** 6881 (BitTorrent TCP+UDP for peer connectivity), 32400 (Plex, host network mode, not routed through Traefik)

## First Start

### qBittorrent

The LinuxServer qBittorrent image generates a temporary admin password on first start:

1. Start the stack: `./arrctl up -d`
2. Get the temporary password: `./arrctl logs qbittorrent 2>&1 | grep "temporary password"`
3. Log in at https://qbit.example.com with user `admin` and the temporary password
4. Change the password in **Tools > Options > Web UI**

### Radarr

Radarr has no temporary password. After starting the stack, run the setup script to configure authentication directives, add qBittorrent as a download client, and set the root media folder. **Run this before `prowlarr-setup`** because Prowlarr needs Radarr's API key, which stabilizes after auth is configured.

```bash
./arrctl up -d
./radarr-setup
```

The script will prompt for your qBittorrent password, then configure:
- **Authentication:** Forms, disabled for local addresses (Authelia handles external auth)
- **Download client:** qBittorrent (host: `qbittorrent`, port: `8080`, category: `radarr`)
- **Root folder:** `/data/media/movies`

Requires `jq` on the host. Uses the Radarr API internally via `docker compose exec` (no Authelia bypass needed).

**Manual setup (without script):**

1. Navigate to https://radarr.example.com (log in via Authelia)
2. Go to **Settings > General > Authentication** and set **Authentication** to `Forms` and **Authentication Required** to `Disabled for Local Addresses`
3. Add qBittorrent as a download client: **Settings > Download Clients > Add** (host: `qbittorrent`, port: `8080`)
4. Add root folder: **Settings > Media Management > Root Folders > Add** (`/data/media/movies`)

### Prowlarr

Prowlarr centralizes indexer management and syncs indexers to Radarr (and future Sonarr). It uses a patched build (`prowlarr-patch/`) that fixes a [FlareSolverr bug](https://github.com/Prowlarr/Prowlarr/issues/2561). Prowlarr normally discards FlareSolverr's solved response body and re-requests with cookies, which fails because `cf_clearance` is TLS-fingerprint-bound. The patch uses the solved body directly. Built from the [`fix/flaresolverr-use-response-body`](https://github.com/quaintops/Prowlarr/tree/fix/flaresolverr-use-response-body) branch. See [`prowlarr-patch/docs/`](prowlarr-patch/docs/) for details on how the patched build is overlaid onto the LinuxServer image.

After running `radarr-setup`, run the Prowlarr setup script to configure authentication (Authelia), connect Prowlarr to Radarr, and set up Byparr:

```bash
./prowlarr-setup
```

The script will:
- **Authentication:** External (Authelia handles auth)
- **Application:** Add Radarr (auto-syncs indexers from Prowlarr to Radarr)
- **Byparr proxy:** Configure Byparr as a FlareSolverr indexer proxy with a `byparr` tag

Requires `jq` on the host. Uses the Prowlarr API internally via `docker compose exec`.

**Manual setup (without script):**

Complete Radarr setup first so its API key is stable.

1. Navigate to https://prowlarr.example.com (log in via Authelia)
2. Go to **Settings > General > Authentication** and set to **External**
3. Add Radarr as an application: **Settings > Apps > Add** (Prowlarr server: `http://prowlarr:9696`, Radarr server: `http://radarr:7878`, API key from Radarr's **Settings > General**)
4. Add Byparr as a FlareSolverr proxy: **Settings > Indexers > Add > FlareSolverr** (host: `http://byparr:8191`, tag: `byparr`)

### Plex

Plex is the media server that serves content organized by Radarr. It runs in host network mode (not behind Traefik) so clients see a local connection. It uses its own authentication (plex.tv accounts) and does not use Authelia.

1. Get a claim token from https://plex.tv/claim (expires in 4 minutes)
2. Start the stack with the claim token: `PLEX_CLAIM="claim-xxxx" ./arrctl up -d`
3. Visit http://plex.example.com:32400/web and sign in with your plex.tv account
4. Add media library: **Settings > Libraries > Add > Movies** with path `/data/media/movies`

The `PLEX_CLAIM` token is only needed on first start to link the server to your plex.tv account. Subsequent starts don't need it.

### Kometa

Kometa (formerly Plex Meta Manager) enriches Plex library metadata: creates collections (trending, top rated, genres, decades), syncs ratings from IMDb/TMDb, and adds resolution/rating overlays to posters. It runs daily at 4 AM and communicates with Plex entirely via its API.

Store TMDb API key in Vault:
```bash
vault kv put secret/kometa tmdb_apikey="YOUR_TMDB_API_KEY"
```

Register at https://www.themoviedb.org/settings/api to get an API key. The Plex token is read automatically from Plex's config, so it doesn't need to be stored in Vault.

Check logs: `./arrctl logs kometa` (should show "Waiting for scheduled run at 04:00")
Manual test run: `./arrctl exec kometa python3 /app/kometa/kometa.py --run --config /config/config.yml`

The `Movies` library name in `kometa/config.yml.template` must match the Plex library name exactly. Edit the template if your library is named differently.

### Byparr

Byparr is a Cloudflare bypass proxy (FlareSolverr-compatible) configured automatically by `prowlarr-setup`. To route an indexer through Byparr, tag it with `byparr` in Prowlarr's UI. Only tagged indexers use the proxy.

## Data Directory Layout

```
/opt/arr/
├── qbittorrent/
│   └── config/          # qBittorrent configuration
├── radarr/
│   └── config/          # Radarr configuration
├── prowlarr/
│   └── config/          # Prowlarr configuration
├── plex/
│   └── config/          # Plex configuration
├── kometa/
│   └── config/          # Kometa runtime state (logs, caches, overlay assets)
└── data/                # Shared download directory (hardlink-friendly)
    ├── torrents/        # Active downloads
    └── media/           # Completed media (organized by Radarr, future: Sonarr)
```

