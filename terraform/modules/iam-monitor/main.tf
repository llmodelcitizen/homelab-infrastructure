# main.tf - IAM activity monitor via EventBridge + Lambda + SNS
#
# Monitors IAM user API calls using CloudTrail management events
# delivered to the default EventBridge bus in us-east-1.
# The cloudtrail module provides a trail with read+write events enabled,
# ensuring read API calls (e.g. ListResourceRecordSets) are also captured.
#
# A Lambda function sits between EventBridge and SNS to format the
# email body with real newlines and a meaningful subject line.

resource "aws_sns_topic" "this" {
  name = "${var.name_prefix}-iam-activity-alerts"

  tags = {
    Name        = "${var.name_prefix}-iam-activity-alerts"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "IAM key usage alerts"
  }
}

# Requires manual confirmation click after first apply
resource "aws_sns_topic_subscription" "this" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = var.recipient_email
}

resource "aws_cloudwatch_event_rule" "this" {
  name        = "${var.name_prefix}-iam-key-usage"
  description = "Matches API calls made by monitored IAM users"

  event_pattern = jsonencode({
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      userIdentity = {
        userName = var.iam_usernames
      }
    }
  })

  tags = {
    Name        = "${var.name_prefix}-iam-key-usage"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "Monitor IAM user API activity"
  }
}

resource "aws_cloudwatch_event_target" "this" {
  rule      = aws_cloudwatch_event_rule.this.name
  target_id = "${var.name_prefix}-iam-alert-email"
  arn       = aws_lambda_function.this.arn
}

# --- Lambda formatter ---

data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"

  source {
    content  = <<-PYTHON
import json
import os
import boto3

sns = boto3.client("sns")

def handler(event, context):
    detail = event.get("detail", {})
    identity = detail.get("userIdentity", {})

    user = identity.get("userName", "N/A")
    event_name = detail.get("eventName", "N/A")

    subject = f"IAM Alert: {user} called {event_name}"

    body = "\n".join([
        "IAM Activity Alert",
        "",
        f"User:       {user}",
        f"Event:      {event_name}",
        f"Time:       {detail.get('eventTime', 'N/A')}",
        f"Region:     {detail.get('awsRegion', 'N/A')}",
        f"Source IP:  {detail.get('sourceIPAddress', 'N/A')}",
        f"Access Key: {identity.get('accessKeyId', 'N/A')}",
        f"User Agent: {detail.get('userAgent', 'N/A')}",
    ])

    sns.publish(
        TopicArn=os.environ["SNS_TOPIC_ARN"],
        Subject=subject[:100],
        Message=body,
    )
PYTHON
    filename = "index.py"
  }
}

resource "aws_lambda_function" "this" {
  function_name    = "${var.name_prefix}-iam-activity-formatter"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "index.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda.arn
  timeout          = 10

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.this.arn
    }
  }

  tags = {
    Name        = "${var.name_prefix}-iam-activity-formatter"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "Format IAM activity alert emails"
  }
}

resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-iam-alert-lambda"

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
    Name        = "${var.name_prefix}-iam-alert-lambda"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "Lambda role for IAM activity alerts"
  }
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.name_prefix}-iam-alert-lambda"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.this.arn
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

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this.arn
}
