# variables.tf - Input variable declarations for iam-monitor module
#
# See ses/variables.tf for detailed comments on variable patterns

variable "iam_usernames" {
  description = "IAM usernames to monitor for API activity"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.iam_usernames) > 0
    error_message = "iam_usernames must contain at least one IAM username"
  }

  validation {
    condition     = alltrue([for name in var.iam_usernames : can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", name))])
    error_message = "Each IAM username must match the IAM naming rules (alphanumeric and +=,.@_- characters, max 64 chars)"
  }
}

variable "recipient_email" {
  description = "Email address for SNS alert notifications"
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
