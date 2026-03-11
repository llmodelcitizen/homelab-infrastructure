# versions.tf - Provider version constraints (separate file per terraform-skill best practices)
#
# Why a separate file?
# - Clear separation of concerns: versions.tf for constraints, main.tf for resources
# - Easier to find and update version constraints
# - Required structure for publishing to Terraform Registry

terraform {
  # Pin to minor version, allow patch updates
  # ~> 1.0 means >= 1.0.0 and < 2.0.0 (any 1.x version)
  required_version = ">= 1.0"

  required_providers {
    # Pessimistic constraint (~>) is recommended for stability
    # ~> 6.0 means >= 6.0.0 and < 7.0.0 (allows minor/patch updates, blocks major)
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
