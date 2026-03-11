# main.tf - CloudTrail S3 sync IAM resources
#
# Creates an IAM user with read-only S3 access to CloudTrail logs.
# Credentials are stored in Secrets Manager for consumption by Ansible.

resource "aws_iam_user" "this" {
  name          = "${var.name_prefix}-cloudtrail-sync-user"
  force_destroy = true

  tags = {
    Name        = "${var.name_prefix}-cloudtrail-sync-user"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "CloudTrail S3 log sync"
  }
}

resource "aws_iam_access_key" "this" {
  user = aws_iam_user.this.name
}

resource "aws_iam_user_policy" "this" {
  name = "${var.name_prefix}-cloudtrail-sync-s3-read"
  user = aws_iam_user.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.s3_bucket_name}"
        Condition = {
          StringLike = {
            "s3:prefix" = ["${var.s3_key_prefix}/*"]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.s3_bucket_name}/${var.s3_key_prefix}/*"
      }
    ]
  })
}

resource "aws_secretsmanager_secret" "this" {
  name                    = "${var.name_prefix}-cloudtrail-sync-credentials"
  description             = "CloudTrail S3 sync credentials"
  recovery_window_in_days = 0

  tags = {
    Name        = "${var.name_prefix}-cloudtrail-sync-credentials"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "CloudTrail S3 sync credentials"
  }
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    aws_access_key_id     = aws_iam_access_key.this.id
    aws_secret_access_key = aws_iam_access_key.this.secret
    s3_bucket             = var.s3_bucket_name
    s3_prefix             = var.s3_key_prefix
  })
}
