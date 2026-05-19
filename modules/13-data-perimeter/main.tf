locals {
  scp_deny_services_content = length(var.deny_services) > 0 ? jsonencode({
    Version = "5.0"
    Statement = [
      {
        Sid      = "DenyDisallowedServices"
        Effect   = "Deny"
        Action   = var.deny_services
        Resource = ["*"]
      }
    ]
  }) : null

  scp_vpcep_only_obs = jsonencode({
    Version = "5.0"
    Statement = [
      {
        Sid      = "DenyOBSOutsideVPCEndpoint"
        Effect   = "Deny"
        Action   = ["obs:*"]
        Resource = ["*"]
        Condition = {
          StringNotEquals = {
            "obs:RequestViaEndpoint" = "true"
          }
        }
      }
    ]
  })

  tags = merge({
    ManagedBy = "terraform"
    Project   = "landing-zone"
    Layer     = "data-perimeter"
  }, var.tags)
}

# ── Service Deny SCP ──────────────────────────────────────────────────────────

resource "huaweicloud_organizations_policy" "deny_services" {
  count = length(var.deny_services) > 0 ? 1 : 0

  name        = "lz-deny-prohibited-services"
  description = "Deny explicitly prohibited services in all member accounts"
  type        = "service_control_policy"
  content     = local.scp_deny_services_content
}

resource "huaweicloud_organizations_policy_attach" "deny_services_root" {
  count = length(var.deny_services) > 0 ? 1 : 0

  policy_id = huaweicloud_organizations_policy.deny_services[0].id
  entity_id = var.root_id
}

# ── OBS VPCEP-only SCP ────────────────────────────────────────────────────────
# Applied in enforce_mode only to avoid breaking access before endpoints are deployed

resource "huaweicloud_organizations_policy" "obs_vpcep_only" {
  count = var.enforce_mode ? 1 : 0

  name        = "lz-obs-vpcep-only"
  description = "Force all OBS traffic through VPC endpoints — deny direct internet access"
  type        = "service_control_policy"
  content     = local.scp_vpcep_only_obs
}

resource "huaweicloud_organizations_policy_attach" "obs_vpcep_only_root" {
  count = var.enforce_mode ? 1 : 0

  policy_id = huaweicloud_organizations_policy.obs_vpcep_only[0].id
  entity_id = var.root_id
}

# ── VPC Endpoint Services ─────────────────────────────────────────────────────

resource "huaweicloud_vpcep_service" "services" {
  for_each = { for s in var.vpc_endpoint_services : s.name => s }

  name             = each.value.name
  server_type      = "Interface"
  vpc_id           = each.value.vpc_id
  approval_enabled = each.value.approval_enabled
  region           = var.home_region

  port_mapping {
    service_port  = 443
    terminal_port = 443
    protocol      = "TCP"
  }

  tags = local.tags
}

# ── VPC Endpoints in Spoke VPCs ───────────────────────────────────────────────

resource "huaweicloud_vpcep_endpoint" "endpoints" {
  for_each = { for e in var.vpc_endpoints : e.name => e }

  service_id  = each.value.service_id
  vpc_id      = each.value.vpc_id
  network_id  = each.value.subnet_id
  enable_dns  = true
  enable_whitelist = false
  region      = var.home_region

  tags = local.tags
}

# ── OBS Built-in VPCEP ────────────────────────────────────────────────────────
# Create a VPCEP for OBS in each spoke — needed before obs_vpcep_only SCP enforce

resource "huaweicloud_vpcep_endpoint" "obs_endpoint" {
  service_id  = "cn.${var.home_region}.obs" # built-in OBS endpoint service
  vpc_id      = length(var.vpc_endpoints) > 0 ? var.vpc_endpoints[0].vpc_id : null
  enable_dns  = true
  enable_whitelist = false
  region      = var.home_region

  tags = local.tags

  count = 0 # disabled by default; enable per-account in spoke composition
}
