# Terraform Modules

### `ses/` - AWS SES Email

Provisions AWS Simple Email Service for sending system notifications.

**Creates:**
- SESv2 domain identity with DKIM authentication
- SESv2 email identity for `recipient_email` (allows receiving in SES sandbox)
- Route53 DNS records (verification TXT, DKIM CNAMEs)
- IAM user with least-privilege SES permissions
- Secrets Manager secret: `<name_prefix>-smtp-credentials`

**Consumed by:** Ansible playbooks configure msmtp on devices to send email via SES. SMTP credentials are mirrored to Vault (`secret/smtp`) by the `vault-mirror` playbook for use by `autheliactl` and `monitoringctl`.

### `email-relay/` - HTTPS Email Relay

Provides an HTTPS email relay via API Gateway + Lambda for hosts with blocked SMTP ports (587/465). Proxies email sends through SES.

**Creates:**
- API Gateway REST API with `/send` endpoint (POST, API key auth, stage `v1`)
- Lambda function (Python 3.12, 10s timeout) calling `ses.send_email()`
- API key with usage plan (10 burst, 5/sec, 1000/day quota)
- Secrets Manager secret: `<name_prefix>-email-relay-credentials` (contains `api_endpoint`, `api_key`)

**Depends on:** `ses` (requires `domain_identity_arn`)

**Consumed by:** Ansible `email-setup` playbook deploys relay scripts on hosts with `use_email_relay=true` (e.g., vps).

### `traefik-aws/` - Traefik DNS & Credentials

Provisions AWS resources for Traefik reverse proxy with Let's Encrypt.

**Creates:**
- Route53 A records (TTL 300) for all service subdomains → server IP
- IAM user with Route53 permissions for ACME DNS-01 challenge
- Secrets Manager secret: `<name_prefix>-traefik-route53-credentials`

**Default services:** `forge`, `frigate`, `companion`, `auth`, `traefik`, `grafana`, `prometheus`, `alertmanager`, `cadvisor`, `qbit`, `radarr`, `prowlarr`, `plex`

To add a new subdomain, edit the `services` default in `traefik-aws/variables.tf`.

**Consumed by:** `traefikctl` wrapper fetches credentials from Vault (`secret/traefik`, mirrored from Secrets Manager by the `vault-mirror` playbook).

### `iam-monitor/` - IAM Key Usage Alerts

Monitors IAM user API activity via EventBridge and sends email alerts via SNS. Matches any API call by monitored IAM users (all AWS services) using CloudTrail events delivered to the default EventBridge bus by the cloudtrail module.

**Creates:**
- SNS topic and email subscription for alerts
- EventBridge rule matching API calls by specified IAM users
- Lambda function (Python 3.12, 10s timeout) to format alert emails

**Monitors:** `<name_prefix>-traefik-dns-user`. Alerts on any API call made with this user's credentials (Route53 DNS-01 challenges during Let's Encrypt cert renewals, or anomalous usage).

**Test email delivery** without triggering real IAM activity:
```bash
aws lambda invoke --function-name <name_prefix>-iam-activity-formatter --cli-binary-format raw-in-base64-out --payload '{"detail":{"userIdentity":{"userName":"test-user","accessKeyId":"AKIAEXAMPLE"},"eventName":"TestEvent","eventTime":"2026-01-01T00:00:00Z","awsRegion":"us-east-1","sourceIPAddress":"1.2.3.4","userAgent":"test"}}' /dev/null
```

**Note:** SNS email subscription requires manual confirmation click after first `terraform apply`.

### `cloudtrail-sync/` - CloudTrail S3 Sync Credentials

Provisions IAM credentials for the cloudtrail-sync container to pull CloudTrail logs from S3.

**Creates:**
- IAM user with read-only S3 access (`s3:ListBucket`, `s3:GetObject`) scoped to `<s3_logs_bucket>/cloudtrail/*`
- IAM access key
- Secrets Manager secret: `<name_prefix>-cloudtrail-sync-credentials`

**Consumed by:** `monitoringctl` wrapper fetches credentials from Vault (`secret/cloudtrail-sync`, mirrored from Secrets Manager by the `vault-mirror` playbook) for the cloudtrail-sync container, which syncs logs from S3 into the Loki/Promtail pipeline.

**Note:** Not added to iam-monitor watch list. Read-only S3 calls every 5 minutes would be noisy.

### `cloudtrail/` - CloudTrail Management Event Logging

Enables a multi-region CloudTrail trail that logs all management events (read + write) to an existing S3 bucket. This ensures EventBridge receives read API calls in addition to the write events already delivered to the default bus, closing a visibility gap for the iam-monitor module.

**Creates:**
- S3 bucket policy on `<s3_logs_bucket>` (merges CloudTrail permissions with existing S3 access logging statement)
- S3 public access block and bucket ownership controls
- CloudTrail trail: `<name_prefix>-management-trail` (multi-region, read+write management events)

**Consumed by:** EventBridge (default bus). Read events now flow to the iam-monitor rule. S3 logs are also synced to Loki by the cloudtrail-sync container.
