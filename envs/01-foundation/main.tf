module "org_foundation" {
  source = "../../modules/01-org-foundation"

  home_region             = var.home_region
  log_archive_email       = var.log_archive_email
  audit_email             = var.audit_email
  log_archive_bucket_name = var.log_archive_bucket_name

  additional_ous = [
    { name = "Workloads" },
    { name = "Production" },
    { name = "NonProduction" },
  ]

  additional_member_accounts = var.additional_member_accounts
  enterprise_project_name    = "landing-zone"
}

module "identity_center" {
  source = "../../modules/02-identity-center"

  home_region = var.home_region
  users       = var.sso_users

  account_assignments = flatten([
    for acct_id in values(module.org_foundation.member_account_ids) : [
      { account_id = acct_id, group_name = "LzAdministrators", permission_set = "LzAdministrator" },
      { account_id = acct_id, group_name = "LzDevelopers", permission_set = "LzDeveloper" },
      { account_id = acct_id, group_name = "LzSecurityAuditors", permission_set = "LzSecurityAuditor" },
    ]
  ])
}

module "iam_baseline" {
  source = "../../modules/03-iam-baseline"

  home_region       = var.home_region
  org_id            = module.org_foundation.organization_id
  master_account_id = var.master_account_id

  enable_mfa          = true
  password_min_length = 14
  password_max_age    = 90
  session_timeout     = 60
}

provider "huaweicloud" {
  region     = var.home_region
  access_key = var.master_access_key
  secret_key = var.master_secret_key
}
