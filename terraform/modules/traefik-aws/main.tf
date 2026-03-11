# main.tf - Traefik AWS resources module
#
# Creates Route53 DNS records and IAM credentials for Traefik's
# Let's Encrypt DNS challenge (ACME protocol)

# Data source to get current AWS region dynamically
# Better than hardcoding "us-east-1" - makes module more portable
data "aws_region" "current" {}

# Route53 A records for services behind traefik
#
# for_each with toset() pattern:
# - toset(var.services) converts ["forge", "frigate"] to a set
# - Creates one record per service: aws_route53_record.services["forge"]
# - Adding/removing services only affects those specific records
#
# Why not count?
# - count uses index: services[0], services[1]
# - Removing "forge" would shift "frigate" from [1] to [0]
# - This causes unnecessary destroy/recreate of the frigate record
resource "aws_route53_record" "services" {
  for_each = toset(var.services)

  zone_id = var.route53_zone_id
  name    = "${each.value}.${var.domain}"
  type    = "A"
  ttl     = 300
  records = [var.server_ip]
}

# IAM user for traefik DNS challenge (Let's Encrypt ACME)
# Traefik needs Route53 permissions to create TXT records for domain validation
resource "aws_iam_user" "this" {
  name          = "${var.name_prefix}-traefik-dns-user"
  force_destroy = true

  tags = {
    Name        = "${var.name_prefix}-traefik-dns-user"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "Traefik Route53 DNS challenge"
  }
}

resource "aws_iam_access_key" "this" {
  user = aws_iam_user.this.name
}

# IAM policy for Route53 DNS challenge
# These are the minimum permissions Traefik needs for ACME DNS-01 challenge
resource "aws_iam_user_policy" "this" {
  name = "${var.name_prefix}-traefik-route53-dns-challenge"
  user = aws_iam_user.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # GetChange: Check if DNS changes have propagated
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        # ChangeResourceRecordSets: Create/delete TXT records for challenge
        # ListResourceRecordSets: List existing records
        # Scoped to specific hosted zone (not "*")
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/${var.route53_zone_id}"
      },
      {
        # ListHostedZonesByName: Find the zone ID by domain name
        # Must be "*" - Route53 doesn't support resource-level permissions for this
        Effect   = "Allow"
        Action   = ["route53:ListHostedZonesByName"]
        Resource = "*"
      }
    ]
  })
}

# Store credentials in Secrets Manager for the traefikctl wrapper to retrieve
resource "aws_secretsmanager_secret" "this" {
  name                    = "${var.name_prefix}-traefik-route53-credentials"
  description             = "AWS credentials for traefik Route53 DNS challenge"
  recovery_window_in_days = 0

  tags = {
    Name        = "${var.name_prefix}-traefik-route53-credentials"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "Traefik DNS challenge credentials"
  }
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    aws_access_key_id     = aws_iam_access_key.this.id
    aws_secret_access_key = aws_iam_access_key.this.secret
    # Use data source instead of hardcoding region
    aws_region         = data.aws_region.current.id
    aws_hosted_zone_id = var.route53_zone_id
  })
}
