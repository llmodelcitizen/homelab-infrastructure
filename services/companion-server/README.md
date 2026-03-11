# Bitfocus Companion (Server)

Docker configuration for [Bitfocus Companion](https://bitfocus.io/companion), a control surface automation tool. This is the server component. For the Raspberry Pi satellite appliances, see the [companion-satellite playbook](../../playbooks/companion-satellite/).

## Data Layout

Runtime data is stored at `/opt/companion`:

```
/opt/companion/
├── v4.2/
│   ├── db.sqlite     # Configuration database
│   └── backups/      # Automatic backups
└── modules/          # Custom modules
```

## Deployment

### 1. Create directories

```bash
sudo mkdir -p /opt/companion
```

### 2. Start services

```bash
./companionctl up -d
```

**Optional:** To set a web UI password, create `.env` with `COMPANION_ADMIN_PASSWORD=yourpassword`.

Access `https://companion.example.com` (or your configured domain).

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 443 | TCP | HTTPS via Traefik (web UI) |
| 16622 | TCP | Companion Satellite API |
| 16623 | TCP | Companion Satellite WebSocket |

**Note:** Port 8000 (web UI) is routed through Traefik for HTTPS access.

## StreamDeck Support

USB devices don't work directly in Docker. StreamDecks connect via [Companion Satellite](https://bitfocus.io/companion-satellite) running on the device host, connecting to port 16622. The hapidecks are provisioned by the [companion-satellite playbook](../../playbooks/companion-satellite/).

