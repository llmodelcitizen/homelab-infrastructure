# main.tf - Email relay via API Gateway + Lambda + SES
#
# Provides an HTTPS endpoint for hosts that cannot reach SES via SMTP
# (e.g. VPS with outbound 587/465 blocked). Clients POST JSON to
# /send with an x-api-key header; Lambda calls ses.send_email().

# --- Lambda function ---

data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"

  source {
    content  = <<-PYTHON
import json
import os
import boto3

ses = boto3.client("ses")

DEFAULT_TO = os.environ["DEFAULT_TO"]
DEFAULT_FROM = os.environ["DEFAULT_FROM"]

def handler(event, context):
    try:
        body = json.loads(event.get("body", "{}"))
    except (json.JSONDecodeError, TypeError):
        return {"statusCode": 400, "body": json.dumps({"error": "Invalid JSON"})}

    subject = body.get("subject")
    message = body.get("body", "")
    to_addr = body.get("to", DEFAULT_TO)
    from_addr = body.get("from", DEFAULT_FROM)

    if not subject:
        return {"statusCode": 400, "body": json.dumps({"error": "subject is required"})}

    ses.send_email(
        Source=from_addr,
        Destination={"ToAddresses": [to_addr]},
        Message={
            "Subject": {"Data": subject},
            "Body": {"Text": {"Data": message}},
        },
    )

    return {"statusCode": 200, "body": json.dumps({"message": "sent"})}
PYTHON
    filename = "index.py"
  }
}

resource "aws_lambda_function" "this" {
  function_name    = "${var.name_prefix}-email-relay"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "index.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda.arn
  timeout          = 10

  environment {
    variables = {
      DEFAULT_TO   = var.recipient_email
      DEFAULT_FROM = "relay@${var.domain}"
    }
  }

  tags = {
    Name        = "${var.name_prefix}-email-relay"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "Email relay via HTTPS for hosts without SMTP access"
  }
}

resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-email-relay-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.name_prefix}-email-relay-lambda"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "Lambda role for email relay"
  }
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.name_prefix}-email-relay-lambda"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = var.ses_domain_identity_arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# --- API Gateway ---

resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.name_prefix}-email-relay"
  description = "Email relay API for hosts without SMTP access"

  tags = {
    Name        = "${var.name_prefix}-email-relay"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "Email relay HTTPS endpoint"
  }
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "send"
}

resource "aws_api_gateway_method" "this" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.this.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "this" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.this.id
  http_method             = aws_api_gateway_method.this.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.this.invoke_arn
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  depends_on = [aws_api_gateway_integration.this]

  # Redeploy when API config changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.this.id,
      aws_api_gateway_method.this.id,
      aws_api_gateway_integration.this.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = "v1"

  tags = {
    Name        = "${var.name_prefix}-email-relay-v1"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
  }
}

# --- API key + usage plan ---

resource "aws_api_gateway_api_key" "this" {
  name    = "${var.name_prefix}-email-relay"
  enabled = true

  tags = {
    Name        = "${var.name_prefix}-email-relay"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
  }
}

resource "aws_api_gateway_usage_plan" "this" {
  name = "${var.name_prefix}-email-relay"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name
  }

  throttle_settings {
    burst_limit = 10
    rate_limit  = 5
  }

  quota_settings {
    limit  = 1000
    period = "DAY"
  }

  tags = {
    Name        = "${var.name_prefix}-email-relay"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
  }
}

resource "aws_api_gateway_usage_plan_key" "this" {
  key_id        = aws_api_gateway_api_key.this.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this.id
}

# --- Lambda permission for API Gateway ---

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

# --- Store credentials in Secrets Manager ---

resource "aws_secretsmanager_secret" "this" {
  name        = "${var.name_prefix}-email-relay-credentials"
  description = "API Gateway endpoint and key for email relay"

  recovery_window_in_days = 0

  tags = {
    Name        = "${var.name_prefix}-email-relay-credentials"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "Email relay API credentials"
  }
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    api_endpoint = "${aws_api_gateway_stage.this.invoke_url}/send"
    api_key      = aws_api_gateway_api_key.this.value
  })
}
