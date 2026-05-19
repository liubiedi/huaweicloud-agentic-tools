locals {
  tags = merge({
    ManagedBy = "terraform"
    Project   = "landing-zone"
    Layer     = "security-center"
  }, var.tags)
}

# ── KMS Keys ──────────────────────────────────────────────────────────────────

resource "huaweicloud_kms_key" "security" {
  for_each = { for k in var.kms_keys : k.alias => k }

  key_alias        = each.value.alias
  key_description  = each.value.description
  rotation_enabled = each.value.rotation_enabled
  region           = var.home_region
  enterprise_project_id = var.enterprise_project_id

  tags = local.tags
}

# ── CSMS Secrets ──────────────────────────────────────────────────────────────

resource "huaweicloud_csms_secret" "secrets" {
  for_each = { for s in var.csms_secrets : s.name => s }

  name        = each.value.name
  description = each.value.description
  kms_key_id  = each.value.kms_key_id != "" ? each.value.kms_key_id : huaweicloud_kms_key.security["lz-secret-key"].id
  secret_string = "PLACEHOLDER — update via console or pipeline after creation"
  region      = var.home_region
}

# ── SecMaster ─────────────────────────────────────────────────────────────────

resource "huaweicloud_secmaster_workspace" "this" {
  name        = var.secmaster_workspace_name
  description = "Landing zone central SOC workspace"
  region      = var.home_region

  tags = local.tags
}

resource "huaweicloud_secmaster_alert_rule" "high_severity" {
  workspace_id = huaweicloud_secmaster_workspace.this.id
  name         = "lz-high-severity-alert"
  description  = "Forward all high severity alerts to SOC team"
  region       = var.home_region

  query_rule = "severity = 'HIGH' OR severity = 'CRITICAL'"
  query_type = "SQL"
  status     = "ENABLED"

  schedule {
    frequency_interval = 5
    frequency_unit     = "MINUTE"
    period_interval    = 1
    period_unit        = "HOUR"
    delay_interval     = 0
    overtime_interval  = 5
  }

  triggers {
    operator        = "GT"
    expression      = "0"
    priority        = 2
    accumulated_times = 1
  }
}

# ── HSS ───────────────────────────────────────────────────────────────────────

resource "huaweicloud_hss_quotas" "enterprise" {
  quotas {
    version = var.hss_version
    count   = var.hss_quota_count
  }

  enterprise_project_id = var.enterprise_project_id
  region                = var.home_region
}

resource "huaweicloud_hss_host_group" "all_hosts" {
  name   = "lz-all-hosts"
  region = var.home_region
}

# ── DBSS ──────────────────────────────────────────────────────────────────────

resource "huaweicloud_dbss_instance" "this" {
  count = var.enable_dbss ? 1 : 0

  name               = "lz-dbss"
  description        = "Landing zone DB security service"
  flavor             = "c3.large.4"
  availability_zone  = var.dbss_availability_zone
  vpc_id             = var.dbss_vpc_id
  subnet_id          = var.dbss_subnet_id
  security_group_id  = var.dbss_security_group_id
  region             = var.home_region
  enterprise_project_id = var.enterprise_project_id

  tags = local.tags
}

# ── SecMaster Playbook for auto-remediation ───────────────────────────────────

resource "huaweicloud_secmaster_playbook" "auto_isolate" {
  workspace_id = huaweicloud_secmaster_workspace.this.id
  name         = "lz-auto-isolate-compromised-host"
  description  = "Automatically isolate a host when HSS detects a critical intrusion"
  region       = var.home_region
  enabled      = false # enable after testing

  version_type = 0
}
