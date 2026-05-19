locals {
  default_scp_deny_root = jsonencode({
    Version = "5.0"
    Statement = [
      {
        Sid      = "DenyRootActions"
        Effect   = "Deny"
        Action   = ["*"]
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "iam:userType" = ["Root"]
          }
        }
      }
    ]
  })

  default_scp_region_boundary = jsonencode({
    Version = "5.0"
    Statement = [
      {
        Sid    = "DenyOutOfRegionOperations"
        Effect = "Deny"
        NotAction = [
          "iam:*",
          "organizations:*",
          "identitycenter:*",
          "billing:*",
          "bss:*",
        ]
        Resource = ["*"]
        Condition = {
          StringNotEquals = {
            "huaweicloud:RequestedRegion" = [var.home_region, "cn-north-4"]
          }
        }
      }
    ]
  })
}

# ── RGC Landing Zone bootstrap ──────────────────────────────────────────────

resource "huaweicloud_rgc_pre_launch_check" "this" {
  home_region = var.home_region
}

resource "huaweicloud_rgc_landing_zone" "this" {
  depends_on = [huaweicloud_rgc_pre_launch_check.this]

  home_region             = var.home_region
  log_archive_email       = var.log_archive_email
  audit_email             = var.audit_email
  log_archive_bucket_name = var.log_archive_bucket_name
}

# ── Organizations trusted services ──────────────────────────────────────────

resource "huaweicloud_organizations_trusted_service" "services" {
  for_each = toset(var.trusted_services)

  service_principal = each.value

  depends_on = [huaweicloud_rgc_landing_zone.this]
}

# ── Additional OUs ───────────────────────────────────────────────────────────

data "huaweicloud_organizations_organization" "current" {
  depends_on = [huaweicloud_rgc_landing_zone.this]
}

resource "huaweicloud_organizations_organizational_unit" "additional" {
  for_each = { for ou in var.additional_ous : ou.name => ou }

  name      = each.value.name
  parent_id = each.value.parent_id != "" ? each.value.parent_id : data.huaweicloud_organizations_organization.current.root_id
}

# ── Member account vending ───────────────────────────────────────────────────

resource "huaweicloud_organizations_account" "members" {
  for_each = { for acct in var.additional_member_accounts : acct.name => acct }

  name        = each.value.name
  email       = each.value.email
  description = each.value.description

  tags = {
    ManagedBy = "terraform"
    Project   = "landing-zone"
  }
}

# ── Default SCPs ─────────────────────────────────────────────────────────────

resource "huaweicloud_organizations_policy" "deny_root" {
  name        = "lz-deny-root-actions"
  description = "Prevent root user actions in all member accounts"
  type        = "service_control_policy"
  content     = local.default_scp_deny_root
}

resource "huaweicloud_organizations_policy" "region_boundary" {
  name        = "lz-region-boundary"
  description = "Restrict workloads to approved regions"
  type        = "service_control_policy"
  content     = local.default_scp_region_boundary
}

resource "huaweicloud_organizations_policy_attach" "deny_root_root" {
  policy_id = huaweicloud_organizations_policy.deny_root.id
  entity_id = data.huaweicloud_organizations_organization.current.root_id
}

resource "huaweicloud_organizations_policy_attach" "region_boundary_root" {
  policy_id = huaweicloud_organizations_policy.region_boundary.id
  entity_id = data.huaweicloud_organizations_organization.current.root_id
}

# ── Custom tag policies ───────────────────────────────────────────────────────

resource "huaweicloud_organizations_policy" "tag_policies" {
  for_each = { for tp in var.tag_policies : tp.name => tp }

  name        = each.value.name
  description = each.value.description
  type        = "tag_policy"
  content     = each.value.content
}

# ── Enterprise project ────────────────────────────────────────────────────────

resource "huaweicloud_enterprise_project" "lz" {
  name        = var.enterprise_project_name
  description = "Landing zone enterprise project for cost allocation"
  status      = 1
}
