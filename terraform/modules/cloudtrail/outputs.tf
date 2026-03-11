# outputs.tf - Module output values for cloudtrail module

output "trail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.this.arn
}

output "trail_name" {
  description = "Name of the CloudTrail trail"
  value       = aws_cloudtrail.this.name
}

output "s3_log_path" {
  description = "S3 path where CloudTrail logs are delivered"
  value       = "s3://${data.aws_s3_bucket.this.id}/${var.s3_key_prefix}/"
}
