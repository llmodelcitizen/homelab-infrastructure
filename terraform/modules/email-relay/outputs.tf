# outputs.tf - Module output values for email-relay
#
# See ses/outputs.tf for detailed comments on output patterns

output "api_endpoint" {
  description = "Full URL for the email relay /send endpoint"
  value       = "${aws_api_gateway_stage.this.invoke_url}/send"
}

output "api_key" {
  description = "API key for authenticating to the email relay"
  value       = aws_api_gateway_api_key.this.value
  sensitive   = true
}

output "secret_name" {
  description = "Name of the Secrets Manager secret containing relay credentials"
  value       = aws_secretsmanager_secret.this.name
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing relay credentials"
  value       = aws_secretsmanager_secret.this.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.this.function_name
}
