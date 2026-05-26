# Foundation env: RGC landing zone + Organizations baseline.
# Wraps modules/01-org-foundation (in this same repo, four directories up).
#
# Apply time: ~25-30 minutes (dominated by RGC bootstrap).
# Most fields here are NonUpdatable — changing them destroys & recreates the LZ.

provider "huaweicloud" {
  region     = var.home_region
  access_key = var.master_access_key
  secret_key = var.master_secret_key

  default_tags = {
    ManagedBy   = "terraform"
    Project     = "landing-zone"
    Environment = var.environment
  }
}

module "org_foundation" {
  source = "../../../../modules/01-org-foundation"

  home_region              = var.home_region
  core_ou_name             = var.core_ou_name
  log_archive_account_name = var.log_archive_account_name
  log_archive_email        = var.log_archive_email
  audit_account_name       = var.audit_account_name
  audit_email              = var.audit_email

  enable_identity_center = var.enable_identity_center
  identity_store_email   = var.identity_store_email

  enable_org_aggregation  = var.enable_org_aggregation
  deny_ungoverned_regions = var.deny_ungoverned_regions

  logging_retention_days        = var.logging_retention_days
  access_logging_retention_days = var.access_logging_retention_days
  logging_multi_az              = var.logging_multi_az

  trusted_services           = var.trusted_services
  additional_ous             = var.additional_ous
  additional_member_accounts = var.additional_member_accounts

  enable_default_deny_root_scp       = var.enable_default_deny_root_scp
  enable_default_region_boundary_scp = var.enable_default_region_boundary_scp

  enable_default_tag_policy        = var.enable_default_tag_policy
  default_tag_policy_required_keys = var.default_tag_policy_required_keys
  tag_policies                     = var.tag_policies

  create_enterprise_project = var.create_enterprise_project
  enterprise_project_name   = var.enterprise_project_name
}
