# Terraform Infrastructure

The Terraform root module is a composition that calls a number of infrastructure modules, each provisioning a distinct AWS capability. All modules read from a shared `vars.yml` (the same file used by Ansible and Docker), and every module that creates credentials stores them in AWS Secrets Manager for one-way mirroring into the local HashiCorp Vault via the `vault_mirror` Ansible playbook.

## Overview

```
terraform/
├── main.tf                      # Root module: backend, provider, module calls
├── versions.tf                  # Provider version constraints
├── outputs.tf                   # Aggregated outputs from all modules
├── backend.tfbackend            # S3 backend config (gitignored)
├── backend.tfbackend.example    # Template for backend config
├── tfinit.sh                    # Wrapper: runs terraform init with backend config
└── modules/
    ├── ses/                     # SES email infrastructure
    ├── email-relay/             # HTTPS email relay (API Gateway + Lambda)
    ├── traefik-aws/             # Traefik Route53 and credentials
    ├── iam-monitor/             # IAM key usage monitoring
    ├── cloudtrail-sync/         # CloudTrail S3 sync credentials
    └── cloudtrail/              # CloudTrail management event logging
```

## Prerequisites

### S3 State Bucket

Terraform stores its state in S3 (configured via the `backend "s3"` block). The bucket must exist before running `terraform init`. Create one:

```bash
aws s3 mb s3://my.state.bucket --region us-east-1
```

Then copy `backend.tfbackend.example` to `backend.tfbackend` and fill in the bucket name, state file path, and region:

```hcl
bucket = "my.state.bucket"
key    = "terraform.tfstate"
region = "us-east-1"
```

### Route53 Hosted Zone

Several modules create DNS records in Route53, so a hosted zone must exist before running `terraform apply`. Create one for your domain:

```bash
aws route53 create-hosted-zone --name example.com --caller-reference $(date +%s)
```

The response includes a `HostedZone.Id` (e.g., `Z0ABC123DEF456`) and four nameservers in `DelegationSet.NameServers`. Set `route53_zone_id` in `vars.yml` to the zone ID:

```yaml
route53_zone_id: Z0ABC123DEF456
```

If your domain registrar is not AWS (e.g., Namecheap, Cloudflare, Google Domains), update the domain's nameservers to the four AWS nameservers returned above. This is typically under "Custom DNS" or "Custom Nameservers" in the registrar's dashboard. Nameserver propagation can take up to 48 hours. If the registrar is Route53 itself, nameservers are configured automatically.

### S3 Logs Bucket

The cloudtrail and cloudtrail-sync modules write to and read from an S3 bucket for CloudTrail log storage. The bucket must exist before running `terraform apply` (Terraform manages its policies, not the bucket itself). Create one:

```bash
aws s3 mb s3://my-logs --region us-east-1
```

Set `s3_logs_bucket` in `vars.yml` to the bucket name:

```yaml
s3_logs_bucket: my-logs
```
## Usage
 
 Use `./tfinit.sh` to initialize: it wraps `terraform init -backend-config=backend.tfbackend`.

```bash
aws sso login
cd terraform/
./tfinit.sh
terraform apply
```

After applying, run the [vault_mirror](../playbooks/vault_mirror/) playbook to mirror credentials from Secrets Manager to Vault. If this is your first time setting up the repo, see the [playbooks README](../playbooks/) for ordered setup instructions.

## Modules

See [modules/README.md](modules/README.md) for detailed documentation on each module.


