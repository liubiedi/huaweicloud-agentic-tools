# Attack defense on the INTERNET protected object (north-south border, where
# these attacks arrive/exfiltrate). The IPS protection mode + virtual patching
# live on the firewall instance itself (05-network network module).

# ── Antivirus: all protocols, block ─────────────────────────────────────────
# One resource per protected object; protocol types per the provider docs:
# 0 HTTP, 1 SMTP, 2 POP3, 3 IMAP4, 4 FTP, 5 SMB, 6 Malicious Access Control.
resource "huaweicloud_cfw_anti_virus" "internet" {
  count = var.enable_anti_virus ? 1 : 0

  object_id = var.internet_object_id

  dynamic "scan_protocol_configs" {
    for_each = [0, 1, 2, 3, 4, 5, 6]
    content {
      protocol_type = scan_protocol_configs.value
      action        = 1 # block
    }
  }
}

# ── Reverse-shell defense: every advanced IPS rule of type 1 -> block IP+on ─
# Action-style: re-apply reasserts; console changes are not seen as drift.
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

  # enterprise_project_id is intentionally NOT set here: it is NonUpdatable, and
  # existing rules were created without it, so setting it fails ("can't be
  # updated"). The rule is targeted by ips_rule_id + object_id; EP scoping lives
  # on the data source that enumerates the rules.
  ips_rule_id    = each.key
  ips_rule_type  = 1
  object_id      = var.internet_object_id
  fw_instance_id = var.fw_instance_id
  param          = each.value.param != "" ? each.value.param : "{}"
  action         = 2 # block IP
  status         = 1 # enabled

  # Every argument here is NonUpdatable; without this the provider fails the
  # plan instead of re-issuing the rule when the action or status changes.
  enable_force_new = "true"
}
