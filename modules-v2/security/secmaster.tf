# --- SecMaster workspace ---
# Note: A single workspace in the security account receives cross-account logs.
# Note: The workspace schema exposes no is_view, view_bind_id or tags.

resource "huaweicloud_secmaster_workspace" "this" {
  count = var.enable_secmaster ? 1 : 0

  name         = var.secmaster_workspace_name
  project_name = var.secmaster_project_name
  description  = "Landing zone central SecMaster workspace (Pattern C)"
}
