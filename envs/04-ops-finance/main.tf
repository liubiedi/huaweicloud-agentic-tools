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

data "terraform_remote_state" "security_audit" {
  backend = "s3"
  config = {
    bucket   = var.tfstate_bucket
    key      = "envs/03-security-audit/terraform.tfstate"
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
  alias  = "ops_monitoring"
  region = var.home_region

  assume_role {
    agency_name = "OrganizationAccountAccessAgency"
    domain_name = var.ops_monitoring_account_domain
  }
}

module "ops_monitoring" {
  source = "../../modules/11-ops-monitoring"

  providers = {
    huaweicloud = huaweicloud.ops_monitoring
  }

  home_region                   = var.home_region
  alert_email_endpoints         = var.alert_email_endpoints
  alert_webhook_endpoints       = var.alert_webhook_endpoints
  enable_functiongraph_runbooks = true
  log_group_id                  = data.terraform_remote_state.security_audit.outputs.security_log_group_id
  enterprise_project_id         = data.terraform_remote_state.foundation.outputs.enterprise_project_id
}

module "finance_governance" {
  source = "../../modules/12-finance-governance"

  providers = {
    huaweicloud = huaweicloud
  }

  home_region = var.home_region
  root_id     = data.terraform_remote_state.foundation.outputs.root_id

  required_tags = [
    { key = "Environment", allowed_values = ["production", "staging", "dev", "sandbox"] },
    { key = "CostCenter", allowed_values = [] },
    { key = "Owner", allowed_values = [] },
    { key = "Project", allowed_values = [] },
  ]
}
