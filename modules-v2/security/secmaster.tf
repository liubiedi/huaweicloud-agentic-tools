# SecMaster workspace + modules + alert rules.
# Pattern C: single workspace in security account; cross-account logs via cloud_log_resource.
#
# The provider's workspace schema has no is_view, view_bind_id or tags.
# The Pattern B (view workspace) upgrade path requires a provider version
# that surfaces those fields.

resource "huaweicloud_secmaster_workspace" "this" {
  count = var.enable_secmaster ? 1 : 0

  name         = var.secmaster_workspace_name
  project_name = var.secmaster_project_name
  description  = "Landing zone central SecMaster workspace (Pattern C)"
}

# ---- Deferred (schema verification pending) ----
#
# huaweicloud_secmaster_alert_rule - many required args (trigger blocks etc.)
#   not surfaced in current var shape. Re-add when triggers/aggregation/etc.
#   schemas are mapped from provider 1.92.
# huaweicloud_secmaster_module - verify module_name vs id, status format.
# huaweicloud_secmaster_cloud_log_resource - verify product_name + log_group_id.
# huaweicloud_secmaster_workspace (member view) - needs is_view/view_bind_id.
#
# Lookup in terraform-provider-huaweicloud/huaweicloud/services/secmaster/
# and re-enable as schemas verify.
