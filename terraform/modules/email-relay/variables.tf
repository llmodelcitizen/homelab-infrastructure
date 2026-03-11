# variables.tf - Input variable declarations for email-relay module
#
# See ses/variables.tf for detailed comments on variable patterns

variable "ses_domain_identity_arn" {
  description = "ARN of the SES domain identity for send permissions"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:aws:ses:", var.ses_domain_identity_arn))
    error_message = "ses_domain_identity_arn must be a valid SES identity ARN"
  }
}

variable "domain" {
  description = "Domain name for default From address"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]\\.[a-z]{2,}$", var.domain))
    error_message = "domain must be a valid domain name (e.g., example.com)"
  }
}

variable "recipient_email" {
  description = "Default recipient email address"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.recipient_email))
    error_message = "recipient_email must be a valid email address"
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
