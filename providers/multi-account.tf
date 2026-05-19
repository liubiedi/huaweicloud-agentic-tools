provider "huaweicloud" {
  region     = var.home_region
  access_key = var.master_access_key
  secret_key = var.master_secret_key

  default_tags = {
    ManagedBy   = "terraform"
    Project     = "landing-zone"
    Environment = "production"
  }
}

provider "huaweicloud" {
  alias  = "network_ops"
  region = var.home_region

  assume_role {
    agency_name = "OrganizationAccountAccessAgency"
    domain_name = var.network_ops_account_domain
  }
}

provider "huaweicloud" {
  alias  = "logging"
  region = "cn-north-4" # CTS org tracker global endpoint

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

provider "huaweicloud" {
  alias  = "ops_monitoring"
  region = var.home_region

  assume_role {
    agency_name = "OrganizationAccountAccessAgency"
    domain_name = var.ops_monitoring_account_domain
  }
}

provider "huaweicloud" {
  alias  = "public_service"
  region = var.home_region

  assume_role {
    agency_name = "OrganizationAccountAccessAgency"
    domain_name = var.public_service_account_domain
  }
}

provider "huaweicloud" {
  alias  = "sandbox"
  region = var.home_region

  assume_role {
    agency_name = "OrganizationAccountAccessAgency"
    domain_name = var.sandbox_account_domain
  }
}
