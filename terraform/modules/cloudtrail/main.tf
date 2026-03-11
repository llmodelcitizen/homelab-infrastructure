# main.tf - CloudTrail management event logging
#
# Enables a multi-region trail that logs all management events (read + write)
# to an existing S3 bucket. This ensures EventBridge receives read events
# (e.g. ListResourceRecordSets) in addition to the write events that the
# default bus already delivers without a trail.

data "aws_caller_identity" "this" {}
data "aws_region" "current" {}

data "aws_s3_bucket" "this" {
  bucket = var.s3_bucket_name
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = data.aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = data.aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = data.aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Preserve existing S3 server access logging permission
      {
        Sid       = "S3ServerAccessLogsPolicy"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${data.aws_s3_bucket.this.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.this.account_id
          }
        }
      },
      # CloudTrail needs to check bucket ACL before delivering logs
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = data.aws_s3_bucket.this.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.id}:${data.aws_caller_identity.this.account_id}:trail/${var.name_prefix}-management-trail"
          }
        }
      },
      # CloudTrail log delivery
      {
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${data.aws_s3_bucket.this.arn}/${var.s3_key_prefix}/AWSLogs/${data.aws_caller_identity.this.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.id}:${data.aws_caller_identity.this.account_id}:trail/${var.name_prefix}-management-trail"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "this" {
  name                          = "${var.name_prefix}-management-trail"
  s3_bucket_name                = data.aws_s3_bucket.this.id
  s3_key_prefix                 = var.s3_key_prefix
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_logging                = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = {
    Name        = "${var.name_prefix}-management-trail"
    Environment = var.name_prefix
    ManagedBy   = "terraform"
    Purpose     = "Management event logging for EventBridge and audit"
  }

  depends_on = [aws_s3_bucket_policy.this]
}
