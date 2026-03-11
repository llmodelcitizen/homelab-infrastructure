# Vault Mirror

Mirrors AWS Secrets Manager credentials to HashiCorp Vault. Run after `terraform apply` to sync credentials that ctl scripts read from Vault. This playbook requires an active AWS session for secretsmanager lookups.

**What it does:**
- Reads SMTP, Traefik, and CloudTrail sync credentials from AWS Secrets Manager
- Writes them to Vault via `vault kv put`
- Validates all required fields before writing

### Run the playbook from myserver:

```bash
ansible-playbook vault_mirror/vault-mirror.yml --become
```

The `--become` flag is required so the playbook can decrypt the age-encrypted Vault token as root. No manual `vault-login` is needed.

### Secrets mirrored

| Secrets Manager | Vault Path |
|---|---|
| `<name_prefix>-smtp-credentials` | `secret/smtp` |
| `<name_prefix>-traefik-route53-credentials` | `secret/traefik` |
| `<name_prefix>-cloudtrail-sync-credentials` | `secret/cloudtrail-sync` |
