# Authelia SSO

[Authelia](https://www.authelia.com/) provides single sign-on (SSO) authentication with two-factor (2FA) support. It acts as a forward-auth provider for Traefik, protecting services that don't have built-in authentication.

## Prerequisites

- Global Traefik running (see [traefik/README.md](../traefik/README.md))
- Vault secret `secret/authelia`. Generate each value with Authelia's built-in secret generator:
  ```bash
  docker run --rm authelia/authelia:latest authelia crypto rand --length 64 --charset alphanumeric
  ```
  Run the generator three times (once per value) and store them in Vault:
  ```bash
  vault kv put secret/authelia \
    jwt_secret=<value> \
    session_secret=<value> \
    storage_encryption_key=<value>
  ```
- Vault secret `secret/smtp` (mirrored from AWS by the [`vault_mirror` playbook](../../playbooks/vault_mirror/))

## Setup

### 1. Create data directories

```bash
sudo mkdir -p /opt/authelia/{data,redis}
```

### 2. Start services

```bash
./autheliactl up -d
```

The `autheliactl` wrapper fetches secrets from Vault and generates `configuration.yml` from the template automatically.

### 3. Initial login

Navigate to a protected service (e.g., https://frigate.example.com) and you'll be redirected to the Authelia login portal.

Default user: `admin` (configured in `users_database.yml`)

### 4. Register 2FA device

After first login, register a TOTP app or WebAuthn device (YubiKey) in the Authelia settings.

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Authelia + Redis containers |
| `autheliactl` | Wrapper script that fetches secrets and generates config |
| `configuration.yml.template` | Template for Authelia config (populated by `autheliactl` via `envsubst`) |
| `users_database.yml` | Local user database (managed by Authelia) |

## Configuration

### Adding users

Edit `users_database.yml` or use the Authelia web UI for password resets. New users need a password hash generated with:

```bash
docker run --rm -it authelia/authelia:latest authelia crypto hash generate argon2
```

The command will prompt for a password and output a full hash string starting with `$argon2id$...`. Paste the entire output as the `password` value in `users_database.yml` (see `users_database.yml.example`).

### Protecting additional services

Traefik routes requests to protected services through the `authelia@docker` middleware, which validates the session with Authelia before allowing access.

1. Add a rule to `configuration.yml.template` for the new service:
   ```yaml
   access_control:
     rules:
       - domain: 'newservice.${BASE_DOMAIN}'
         policy: bypass
   ```

2. Or add the middleware to protect it in the service's docker-compose.yml:
   ```yaml
   labels:
     - "traefik.http.routers.myservice.middlewares=authelia@docker"
   ```

### Session timeouts

| Setting | Value | Meaning |
|---------|-------|---------|
| `inactivity` | `1d` | Session expires after 1 day of inactivity |
| `expiration` | `1d` | Session expires after 1 day regardless of activity |
| `remember_me` | `-1` | "Remember Me" sessions never expire |

### WebAuthn (YubiKey) settings

The `selection_criteria.user_verification: discouraged` setting allows touch-only authentication without PIN entry.

## Secrets

| Source | Secret | Used For |
|--------|--------|----------|
| Vault | `secret/authelia` | JWT, session, storage encryption keys |
| Vault | `secret/smtp` | Password reset emails via SES (mirrored from AWS by [`vault_mirror`](../../playbooks/vault_mirror/)) |

## References

- [Authelia Documentation](https://www.authelia.com/docs/)
- [Traefik ForwardAuth](https://doc.traefik.io/traefik/middlewares/http/forwardauth/)
