# outputs.tf - Traefik module outputs
#
# These outputs are consumed by:
# - Root module (terraform/outputs.tf) for visibility
# - traefikctl wrapper script (via Secrets Manager)

output "secret_name" {
  description = "Name of the Secrets Manager secret containing traefik credentials"
  value       = aws_secretsmanager_secret.this.name
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing traefik credentials"
  value       = aws_secretsmanager_secret.this.arn
}

output "access_key_id" {
  description = "IAM access key ID for traefik DNS challenge"
  value       = aws_iam_access_key.this.id
  sensitive   = true
}

output "secret_access_key" {
  description = "IAM secret access key for traefik DNS challenge"
  value       = aws_iam_access_key.this.secret
  sensitive   = true
}

# Map output using for expression
# Transforms: { "forge" = resource, "frigate" = resource }
# Into: { "forge" = "forge.example.com", "frigate" = "frigate.example.com" }
#
# For expression syntax: { for key, value in collection : new_key => new_value }
output "service_fqdns" {
  description = "Map of service names to their FQDNs"
  value       = { for k, v in aws_route53_record.services : k => v.fqdn }
}
