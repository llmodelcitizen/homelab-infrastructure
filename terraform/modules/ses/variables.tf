# variables.tf - Input variable declarations
#
# Variable block ordering (per terraform-skill):
# 1. description (ALWAYS required - helps users understand the variable)
# 2. type (explicit type constraints catch errors early)
# 3. default (sensible defaults where appropriate)
# 4. sensitive (for secrets, Terraform 0.14+)
# 5. nullable (Terraform 1.1+ - controls whether null is valid)
# 6. validation (custom validation rules)

variable "domain" {
  description = "Domain name for SES email sending"
  type        = string

  # nullable = false (Terraform 1.1+)
  # Without this, passing null would be valid and could cause confusing errors
  # With this, Terraform rejects null values with a clear error
  nullable = false

  # validation block - custom validation rules
  # condition: must evaluate to true for valid input
  # can() function returns false instead of error, useful for regex validation
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]\\.[a-z]{2,}$", var.domain))
    error_message = "domain must be a valid domain name (e.g., example.com)"
  }
}

variable "recipient_email" {
  description = "Email address for SES verification"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.recipient_email))
    error_message = "recipient_email must be a valid email address"
  }
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS verification"
  type        = string
  nullable    = false

  # Route53 zone IDs always start with 'Z' followed by alphanumeric characters
  validation {
    condition     = can(regex("^Z[A-Z0-9]{10,32}$", var.route53_zone_id))
    error_message = "route53_zone_id must be a valid Route53 hosted zone ID (starts with Z followed by alphanumeric characters)"
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
