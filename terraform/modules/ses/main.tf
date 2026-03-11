# main.tf - SES module resources
#
# This is a "resource module" in terraform-skill terminology:
# - Single logical group of related resources (SES + SMTP credentials)
# - Highly reusable across projects
# - No hardcoded values - everything parameterized via variables or data sources

data "aws_region" "current" {}

# SES domain identity using v2 API (newer, more features)
# "this" naming convention: use when module creates only ONE of this resource type
# It signals "this is THE domain identity for this module"
resource "aws_sesv2_email_identity" "this" {
  email_identity = var.domain

  # DKIM (DomainKeys Identified Mail) for email authentication
  # RSA_2048_BIT is the strongest available option
  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }
}

# Separate email identity for recipient verification
# Not named "this" because we have multiple email identities
resource "aws_sesv2_email_identity" "recipient" {
  email_identity = var.recipient_email
}

# Route53 TXT record for SES domain verification
resource "aws_route53_record" "ses_verification" {
  zone_id = var.route53_zone_id
  name    = "_amazonses.${var.domain}"
  type    = "TXT"
  ttl     = 600
  records = [aws_sesv2_email_identity.this.dkim_signing_attributes[0].tokens[0]]
}

# Route53 DKIM records for email authentication
#
# Why count = 3 instead of for_each:
# - AWS SES always generates exactly 3 DKIM tokens
# - for_each with dynamic values (tokens) requires a second apply
# - count = 3 is static, allowing single-apply deployment
#
# The tokens list order is stable within a single SES identity
resource "aws_route53_record" "ses_dkim" {
  count = 3

  zone_id = var.route53_zone_id
  name    = "${aws_sesv2_email_identity.this.dkim_signing_attributes[0].tokens[count.index]}._domainkey.${var.domain}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_sesv2_email_identity.this.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}

# IAM user for SMTP authentication
# "this" naming: only one IAM user in this module
#
# force_destroy = true:
# - Allows terraform destroy even if access keys exist
# - Without this, destroy fails if user has active keys
# - Safe for infrastructure managed entirely by Terraform
resource "aws_iam_user" "this" {
  name          = "${var.name_prefix}-smtp-user"
  force_destroy = true

  # Tags for resource management and cost allocation
  # ManagedBy tag helps identify Terraform-managed resources
  tags = {
    Name        = "${var.name_prefix}-smtp-user"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "SES SMTP email sending"
  }
}

resource "aws_iam_access_key" "this" {
  user = aws_iam_user.this.name
}

# IAM policy with least-privilege permissions
resource "aws_iam_user_policy" "this" {
  name = "${var.name_prefix}-ses-send-policy"
  user = aws_iam_user.this.name

  # jsonencode() converts HCL to JSON - cleaner than heredoc JSON strings
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        # Restrict to specific domain identity (not "*")
        # This follows least-privilege principle
        Resource = aws_sesv2_email_identity.this.arn
      }
    ]
  })
}

# Store SMTP credentials in AWS Secrets Manager
# This keeps secrets out of Terraform state where possible
resource "aws_secretsmanager_secret" "this" {
  name        = "${var.name_prefix}-smtp-credentials"
  description = "SMTP credentials for AWS SES email sending"

  # recovery_window_in_days = 0:
  # - Allows immediate deletion (no 7-30 day waiting period)
  # - Useful for development/testing; consider longer window for production
  recovery_window_in_days = 0

  tags = {
    Name        = "${var.name_prefix}-smtp-credentials"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "SES SMTP credentials"
  }
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    smtp_username = aws_iam_access_key.this.id
    smtp_password = aws_iam_access_key.this.ses_smtp_password_v4
    smtp_endpoint = "email-smtp.${data.aws_region.current.id}.amazonaws.com"
  })
}
