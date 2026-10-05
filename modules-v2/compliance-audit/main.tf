# --- Provider requirements ---

terraform {
  required_version = ">= 1.6.3"
  required_providers {
    huaweicloud = { source = "huaweicloud/huaweicloud", version = "~> 1.87" }
  }
}

locals {
  # Account-name substitution
  audit_bucket_name = replace(var.audit_bucket_name, "{account-name}", var.account_name)
  kms_audit_alias   = replace(var.kms_audit_alias, "{account-name}", var.account_name)
}
