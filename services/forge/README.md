# Forgejo Self-Hosted Git Forge

Self-hosted Git forge using Forgejo with PostgreSQL database.

## Data Layout

All persistent data is stored in `/opt/forge/`:

```
/opt/forge/
├── data/              # Forgejo data (git repos, LFS, avatars)
└── postgres/          # PostgreSQL data
```

## Vault Secrets

Generate secrets and store in Vault:

```bash
vault kv put secret/forge \
  db_password="$(openssl rand -hex 32)" \
  secret_key="$(openssl rand -hex 32)" \
  internal_token="$(openssl rand -hex 32)"
```

## Deployment

### 1. Create directories

```bash
sudo mkdir -p /opt/forge/{data,postgres}
```

### 2. Start services

The `forgectl` script reads the domain from `../../vars.yml` and fetches secrets from Vault:

```bash
./forgectl up -d
```

### 3. Verify

```bash
# Check all services are running
./forgectl ps
```

### 4. Configure via web UI

Access `https://forge.example.com` and complete the setup wizard. You can find the requisite SMTP settings in either Vault or Secrets Manager.

```bash
aws secretsmanager get-secret-value --secret-id <name_prefix>-smtp-credentials --query SecretString --output text | jq
```

## Operations

Use `./forgectl` instead of `docker compose` to avoid environment variable warnings.

### View logs

```bash
./forgectl logs -f
./forgectl logs -f forgejo
./forgectl logs -f db
```

### Stop services

```bash
./forgectl down
```

### Update images

```bash
./forgectl pull
./forgectl up -d
```

### Rotate secrets

Regenerate secrets in Vault, then recreate containers:

```bash
vault kv put secret/forge \
  db_password="$(openssl rand -hex 32)" \
  secret_key="$(openssl rand -hex 32)" \
  internal_token="$(openssl rand -hex 32)"

./forgectl up -d --force-recreate
```

**Note:** If rotating `db_password`, you must also update PostgreSQL (see Troubleshooting).

### Access Forgejo CLI

```bash
./forgectl exec -u git forgejo forgejo admin ...
```

## Disaster Recovery (without Vault)

Repos are plain git data on disk - Vault secrets aren't used for encryption.

**If containers are still running**, secrets are baked in:

```bash
docker exec forge-forgejo-1 env | grep FORGEJO
docker exec forge-db-1 env | grep POSTGRES
```

**Direct repo access** - repos are bare git at `/opt/forge/data/git/repositories/`:

```bash
git clone /opt/forge/data/git/repositories/<user>/<repo>.git
```

**Database files** are at `/opt/forge/postgres/`.

## Troubleshooting

### Database connection issues

```bash
# Check database health
./forgectl exec db pg_isready -U forgejo

# View database logs
./forgectl logs db
```

### Database password mismatch

If you see `password authentication failed for user "forgejo"`, the Vault password doesn't match what PostgreSQL was initialized with.

**Why:** PostgreSQL only reads `POSTGRES_PASSWORD` during initial database creation. After that, changing Vault secrets won't update the existing database password.

**Fix without data loss:**

```bash
# Get current password from Vault
vault kv get -field=db_password secret/forge

# Update PostgreSQL to match
./forgectl exec db psql -U forgejo -c "ALTER USER forgejo PASSWORD 'paste-password-here';"
```

### Forgejo not starting

```bash
# Check Forgejo logs
./forgectl logs forgejo

# Verify database is healthy first
./forgectl ps db
```
