data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket   = var.tfstate_bucket
    key      = "envs/01-foundation/terraform.tfstate"
    region   = var.home_region
    endpoints = {
      s3 = "https://obs.${var.home_region}.myhuaweicloud.com"
    }
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
  }
}

provider "huaweicloud" {
  region     = var.home_region
  access_key = var.master_access_key
  secret_key = var.master_secret_key
}

provider "huaweicloud" {
  alias  = "logging"
  region = "cn-north-4" # CTS org tracker global endpoint — must not change

  assume_role {
    agency_name = "OrganizationAccountAccessAgency"
    domain_name = var.logging_account_domain
  }
}

provider "huaweicloud" {
  alias  = "security_ops"
  region = var.home_region

  assume_role {
    agency_name = "OrganizationAccountAccessAgency"
    domain_name = var.security_ops_account_domain
  }
}

module "ops_monitoring_early" {
  source = "../../modules/11-ops-monitoring"

  providers = { huaweicloud = huaweicloud }

  home_region                  = var.home_region
  alert_email_endpoints        = var.alert_email_endpoints
  enable_functiongraph_runbooks = false
  enterprise_project_id        = data.terraform_remote_state.foundation.outputs.enterprise_project_id
}

module "audit_logging" {
  source = "../../modules/09-audit-logging"

  providers = {
    huaweicloud = huaweicloud.logging
  }

  home_region               = var.home_region
  log_archive_bucket        = var.log_archive_bucket
  log_archive_bucket_region = var.home_region
  kms_key_id                = module.security_center.audit_kms_key_id
  smn_topic_urn             = module.ops_monitoring_early.smn_topic_urn
  enterprise_project_id     = data.terraform_remote_state.foundation.outputs.enterprise_project_id
}

module "security_center" {
  source = "../../modules/08-security-center"

  providers = {
    huaweicloud = huaweicloud.security_ops
  }

  home_region              = var.home_region
  hss_quota_count          = var.hss_quota_count
  enable_dbss              = var.enable_dbss
  dbss_availability_zone   = "${var.home_region}a"
  dbss_vpc_id              = var.dbss_vpc_id
  dbss_subnet_id           = var.dbss_subnet_id
  dbss_security_group_id   = var.dbss_security_group_id
  smn_topic_urn            = module.ops_monitoring_early.smn_topic_urn
  lts_log_group_id         = module.audit_logging.security_log_group_id
  enterprise_project_id    = data.terraform_remote_state.foundation.outputs.enterprise_project_id
}

module "compliance_config" {
  source = "../../modules/10-compliance-config"

  providers = {
    huaweicloud = huaweicloud.security_ops
  }

  home_region            = var.home_region
  obs_recorder_bucket    = var.log_archive_bucket
  smn_topic_urn          = module.ops_monitoring_early.smn_topic_urn
  aggregator_account_ids = values(data.terraform_remote_state.foundation.outputs.member_account_ids)
  enterprise_project_id  = data.terraform_remote_state.foundation.outputs.enterprise_project_id
}
