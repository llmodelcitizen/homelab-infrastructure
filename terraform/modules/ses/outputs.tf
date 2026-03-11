# outputs.tf - Module output values
#
# Output block ordering (per terraform-skill):
# 1. description (explain what this output is for)
# 2. value
# 3. sensitive (mark sensitive data to prevent accidental exposure)
#
# Output naming convention: {name}_{type}_{attribute}
# Don't prefix with "this_" even when referencing "this" resources

output "smtp_secret_name" {
  description = "Name of the Secrets Manager secret containing SMTP credentials"
  value       = aws_secretsmanager_secret.this.name
}

output "smtp_secret_arn" {
  description = "ARN of the Secrets Manager secret containing SMTP credentials"
  value       = aws_secretsmanager_secret.this.arn
}

# sensitive = true:
# - Prevents value from appearing in terraform plan/apply output
# - Still stored in state file (use external secret management for true security)
# - Required for credentials, API keys, passwords
output "smtp_username" {
  description = "SMTP username (IAM access key ID)"
  value       = aws_iam_access_key.this.id
  sensitive   = true
}

output "smtp_password" {
  description = "SMTP password (SES SMTP password)"
  value       = aws_iam_access_key.this.ses_smtp_password_v4
  sensitive   = true
}

output "domain_identity_arn" {
  description = "ARN of the SES domain identity"
  value       = aws_sesv2_email_identity.this.arn
}

output "dkim_tokens" {
  description = "DKIM tokens for DNS configuration"
  value       = aws_sesv2_email_identity.this.dkim_signing_attributes[0].tokens
}
