# --- Internet attack defense ---
# Note: Firewall IPS mode and virtual patching are managed in 05-network.

# --- Antivirus protection ---
resource "huaweicloud_cfw_anti_virus" "internet" {
  count = var.enable_anti_virus ? 1 : 0

  object_id = var.internet_object_id

  dynamic "scan_protocol_configs" {
    for_each = [0, 1, 2, 3, 4, 5, 6]
    content {
      protocol_type = scan_protocol_configs.value
      # Block action
      action = 1
    }
  }
}

# --- Reverse-shell protection ---
# Note: Reapplying reasserts settings; console changes are not detected as drift.
data "huaweicloud_cfw_advanced_ips_rules" "internet" {
  count = var.enable_reverse_shell_defense ? 1 : 0

  object_id             = var.internet_object_id
  enterprise_project_id = var.enterprise_project_id
}

resource "huaweicloud_cfw_advanced_ips_rule" "reverse_shell" {
  for_each = var.enable_reverse_shell_defense ? {
    for r in data.huaweicloud_cfw_advanced_ips_rules.internet[0].advanced_ips_rules :
    r.ips_rule_id => r if tostring(r.ips_rule_type) == "1"
  } : {}

  # Note: Keep enterprise_project_id unset on existing rules; project scoping belongs to the lookup.
  ips_rule_id    = each.key
  ips_rule_type  = 1
  object_id      = var.internet_object_id
  fw_instance_id = var.fw_instance_id
  param          = each.value.param != "" ? each.value.param : "{}"
  action         = var.reverse_shell_action
  # Enabled status
  status = 1

  # Note: Changed immutable arguments require rule replacement.
  enable_force_new = "true"
}
