# outputs.tf - Root module outputs
#
# Aggregates outputs from child modules for visibility
# Run `terraform output` to see all values
# Run `terraform output -json` for machine-readable format

# SES outputs
output "smtp_secret_name" {
  description = "Name of the Secrets Manager secret containing SMTP credentials"
  value       = module.ses.smtp_secret_name
}

output "smtp_secret_arn" {
  description = "ARN of the Secrets Manager secret containing SMTP credentials"
  value       = module.ses.smtp_secret_arn
}

# Email relay outputs
output "email_relay_api_endpoint" {
  description = "HTTPS endpoint for the email relay"
  value       = module.email_relay.api_endpoint
}

output "email_relay_secret_name" {
  description = "Name of the Secrets Manager secret containing email relay credentials"
  value       = module.email_relay.secret_name
}

# Traefik outputs
output "traefik_secret_name" {
  description = "Name of the Secrets Manager secret containing traefik Route53 credentials"
  value       = module.traefik.secret_name
}

# Map output from for_each resources
# Example value: { "forge" = "forge.example.com", "frigate" = "frigate.example.com" }
output "traefik_service_fqdns" {
  description = "Map of service names to their FQDNs"
  value       = module.traefik.service_fqdns
}

# CloudTrail sync outputs
output "cloudtrail_sync_secret_name" {
  description = "Name of the Secrets Manager secret containing CloudTrail sync credentials"
  value       = module.cloudtrail_sync.secret_name
}

# IAM monitor outputs
output "iam_monitor_sns_topic_arn" {
  description = "ARN of the SNS topic for IAM activity alerts"
  value       = module.iam_monitor.sns_topic_arn
}

output "iam_monitor_event_rule_arn" {
  description = "ARN of the EventBridge rule for IAM key usage monitoring"
  value       = module.iam_monitor.event_rule_arn
}

# CloudTrail outputs
output "cloudtrail_trail_arn" {
  description = "ARN of the CloudTrail management event trail"
  value       = module.cloudtrail.trail_arn
}

output "cloudtrail_s3_log_path" {
  description = "S3 path where CloudTrail logs are delivered"
  value       = module.cloudtrail.s3_log_path
}
