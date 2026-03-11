# outputs.tf - Module output values for iam-monitor module

output "sns_topic_arn" {
  description = "ARN of the SNS topic for IAM activity alerts"
  value       = aws_sns_topic.this.arn
}

output "event_rule_arn" {
  description = "ARN of the EventBridge rule matching IAM user API calls"
  value       = aws_cloudwatch_event_rule.this.arn
}
