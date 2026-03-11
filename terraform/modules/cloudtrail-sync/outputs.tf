# outputs.tf - CloudTrail sync module outputs
#
# These outputs are consumed by:
# - Root module (terraform/main.tf) for visibility

output "access_key_id" {
  description = "IAM access key ID for CloudTrail S3 sync"
  value       = aws_iam_access_key.this.id
  sensitive   = true
}

output "secret_access_key" {
  description = "IAM secret access key for CloudTrail S3 sync"
  value       = aws_iam_access_key.this.secret
  sensitive   = true
}

output "iam_user_name" {
  description = "Name of the IAM user for CloudTrail S3 sync"
  value       = aws_iam_user.this.name
}

output "secret_name" {
  description = "Name of the Secrets Manager secret containing CloudTrail sync credentials"
  value       = aws_secretsmanager_secret.this.name
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing CloudTrail sync credentials"
  value       = aws_secretsmanager_secret.this.arn
}
