# main.tf - Root module configuration
#
# This is a "composition" in terraform-skill terminology:
# - Combines multiple infrastructure modules
# - Contains environment-specific values
# - Not meant to be reusable (unlike the modules it calls)

terraform {
  # Configured via backend.tfbackend - see backend.tfbackend.example
  backend "s3" {}
}

provider "aws" {
  region = local.common_vars.aws_region
}

locals {
  # Load shared variables from YAML (used by both Terraform and Ansible)
  # This pattern keeps configuration DRY across tools
  common_vars = yamldecode(file("${path.module}/../vars.yml"))

  # Validate required keys exist in vars.yml
  # This fails fast with a clear error if keys are missing
  # The tobool() trick converts a string to an error message on failure
  required_keys = ["aws_region", "domain", "recipient_email", "route53_zone_id", "myserver_ip", "s3_logs_bucket", "name_prefix"]
  _validate_keys = [
    for key in local.required_keys :
    local.common_vars[key] != null ? true : tobool("Missing required key in vars.yml: ${key}")
  ]
}

# Module calls follow the pattern:
# - source: relative path to module directory
# - variables: passed explicitly (no implicit variable inheritance)

module "ses" {
  source          = "./modules/ses"
  domain          = local.common_vars.domain
  recipient_email = local.common_vars.recipient_email
  route53_zone_id = local.common_vars.route53_zone_id
  name_prefix     = local.common_vars.name_prefix
}

module "email_relay" {
  source                  = "./modules/email-relay"
  ses_domain_identity_arn = module.ses.domain_identity_arn
  domain                  = local.common_vars.domain
  recipient_email         = local.common_vars.recipient_email
  name_prefix             = local.common_vars.name_prefix
}

module "traefik" {
  source          = "./modules/traefik-aws"
  domain          = local.common_vars.domain
  route53_zone_id = local.common_vars.route53_zone_id
  server_ip       = local.common_vars.myserver_ip
  name_prefix     = local.common_vars.name_prefix
}

module "iam_monitor" {
  source          = "./modules/iam-monitor"
  iam_usernames   = ["${local.common_vars.name_prefix}-traefik-dns-user"]
  recipient_email = local.common_vars.recipient_email
  name_prefix     = local.common_vars.name_prefix
}

module "cloudtrail" {
  source         = "./modules/cloudtrail"
  s3_bucket_name = local.common_vars.s3_logs_bucket
  name_prefix    = local.common_vars.name_prefix
}

module "cloudtrail_sync" {
  source         = "./modules/cloudtrail-sync"
  s3_bucket_name = local.common_vars.s3_logs_bucket
  name_prefix    = local.common_vars.name_prefix
}
