output "secmaster_workspace_id" {
  description = "SecMaster workspace ID"
  value       = var.enable_secmaster ? huaweicloud_secmaster_workspace.this[0].id : null
}

# secmaster_alert_rule outputs deferred until that resource is re-enabled.

# HSS + DBSS outputs deferred until those modules are re-enabled (see hss.tf, dbss.tf).
