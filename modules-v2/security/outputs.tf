# --- Security outputs ---

output "secmaster_workspace_id" {
  description = "SecMaster workspace ID"
  value       = var.enable_secmaster ? huaweicloud_secmaster_workspace.this[0].id : null
}




