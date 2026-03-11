# variables.tf - Input variable declarations for traefik-aws module
#
# See ses/variables.tf for detailed comments on variable patterns

variable "domain" {
  description = "Domain name for Route53 records"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]\\.[a-z]{2,}$", var.domain))
    error_message = "domain must be a valid domain name (e.g., example.com)"
  }
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^Z[A-Z0-9]{10,32}$", var.route53_zone_id))
    error_message = "route53_zone_id must be a valid Route53 hosted zone ID (starts with Z followed by alphanumeric characters)"
  }
}

variable "server_ip" {
  description = "IP address of the server running traefik"
  type        = string
  nullable    = false

  # Simple IPv4 validation (doesn't check octet ranges 0-255)
  # For production, consider more comprehensive validation
  validation {
    condition     = can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.server_ip))
    error_message = "server_ip must be a valid IPv4 address (e.g., 192.168.1.1)"
  }
}

# Variable with default value
# Users can override this to add more services or remove existing ones
variable "services" {
  description = "List of service subdomains to create Route53 A records for"
  type        = list(string)
  default     = ["forge", "frigate", "companion", "auth", "traefik", "grafana", "prometheus", "alertmanager", "cadvisor", "qbit", "radarr", "prowlarr", "plex"]

  # Validation ensures at least one service (empty list would be pointless)
  validation {
    condition     = length(var.services) > 0
    error_message = "services must contain at least one service name"
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
