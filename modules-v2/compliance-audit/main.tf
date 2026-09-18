locals {
  # Substitute the {account-name} token with the account this module deploys into.
  audit_bucket_name   = replace(var.audit_bucket_name, "{account-name}", var.account_name)
  kms_audit_alias     = replace(var.kms_audit_alias, "{account-name}", var.account_name)
}
