# variables.tf - Input variable declarations for cloudtrail module
#
# See ses/variables.tf for detailed comments on variable patterns

variable "s3_bucket_name" {
  description = "Name of the existing S3 bucket for CloudTrail log delivery"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.s3_bucket_name))
    error_message = "s3_bucket_name must be a valid S3 bucket name (lowercase alphanumeric, hyphens, dots, 3-63 chars)"
  }
}

variable "s3_key_prefix" {
  description = "S3 key prefix for CloudTrail log files"
  type        = string
  default     = "cloudtrail"
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_-]+$", var.s3_key_prefix))
    error_message = "s3_key_prefix must contain only alphanumeric characters, hyphens, underscores, forward slashes"
  }
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "ew"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric"
  }
}
