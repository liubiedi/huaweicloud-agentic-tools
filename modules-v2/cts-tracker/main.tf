# Minimal CTS tracker - enables the account's system tracker without any OBS or
# LTS transfer. Audit events are still recorded (CTS console, ~7-day retention)
# so the account pays no OBS/LTS storage charges. Deployed per-account by the
# env-05 observability codegen for accounts in AuditSettings.cts_no_transfer_accounts.
#
# The central org tracker (module 06-compliance-audit, in the CTS-admin account)
# already aggregates every member account to the central bucket/LTS; this is only
# for turning CTS on cheaply in additional accounts.

resource "huaweicloud_cts_tracker" "this" {
  enabled              = true
  organization_enabled = false
  lts_enabled          = false # provider default is true - MUST be false to avoid LTS transfer charges
  # bucket_name intentionally omitted -> no OBS transfer.

  tags = var.tags
}
