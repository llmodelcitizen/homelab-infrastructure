# Email Setup

Configures email sending on managed hosts. Supports two transports: direct SMTP via msmtp (default) and HTTPS relay via API Gateway (for hosts with blocked SMTP ports like 587/465). Hosts with `use_email_relay=true` in inventory get the relay transport; all others get SMTP.

This playbook requires an active AWS session for secretsmanager lookups. Vault lookup is not supported here for better ssh boundaries.

### Run remotely

```bash
ansible-playbook email/email-setup.yml
```

### Run locally on myserver

```bash
ansible-playbook email/email-setup.yml --limit myserver --connection local
```

## What it deploys

### SMTP transport (default)

- Installs `msmtp`, `msmtp-mta`, and `mailutils`
- Configures `/etc/msmtprc` with SES SMTP credentials
- Creates `/etc/aliases` to route local user mail to `recipient_email`
- Deploys `/usr/local/bin/send-mail` wrapper

### Relay transport (`use_email_relay=true`)

- Installs `curl` and `jq`
- Deploys `/usr/local/bin/send-mail` (API Gateway version)
- Deploys `/usr/local/bin/mail` drop-in replacement for mailutils

### `/usr/local/bin/send-mail`

Primary script for sending email. Same interface on both transports.

```bash
send-mail "subject" "body" [recipient]
```

- Defaults recipient to `recipient_email` from `vars.yml`
- Sets `From:` to `<hostname>@<domain>`

### `/usr/local/bin/mail` (relay only)

Drop-in replacement for `/usr/bin/mail` (mailutils) so that `unattended-upgrades` and other system tools that shell out to `mail` work transparently without msmtp.

```bash
echo "body" | mail -s "subject" recipient
```

## Troubleshooting

**SMTP hosts:**
```bash
# Check msmtp config
sudo cat /etc/msmtprc

# Check msmtp log
cat /var/log/msmtp.log

# Test SMTP connectivity
telnet email-smtp.us-east-1.amazonaws.com 587
```

**Relay hosts:**
```bash
# Test relay directly
/usr/local/bin/send-mail "Test" "Test body"
```
