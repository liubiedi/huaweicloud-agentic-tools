# --- Service control policies ---
# Note: Guardrails are packed into documents to respect attachment and size limits.

locals {
  _scps = var.scps

  # Allowed organization path
  # Note: StringNotMatch treats the trailing * as a wildcard; StringNotLike does not.
  _org_path     = var.org_id != "" && var.root_ou_id != "" ? "${var.org_id}/${var.root_ou_id}/*" : ""
  _ram_org_path = local._scps.deny_unauthorized_ram_share.allowed_org_path != "" ? local._scps.deny_unauthorized_ram_share.allowed_org_path : local._org_path
  _rms_org_path = local._scps.deny_unauthorized_rms_aggregation.allowed_org_path != "" ? local._scps.deny_unauthorized_rms_aggregation.allowed_org_path : local._org_path

  # Guardrail statements

  # Organization membership protection
  stmt_deny_leave_org = {
    Sid      = "DenyLeaveOrganization"
    Effect   = "Deny"
    Action   = ["organizations:organizations:leave"]
    Resource = ["*"]
  }

  # Root user restriction
  # Note: Bool avoids matching non-root requests where the principal flag is absent.
  stmt_deny_root_user = {
    Sid      = "DenyRootUserAllActions"
    Effect   = "Deny"
    Action   = [for s in local._scps.deny_root_user.services : "${s}:*:*"]
    Resource = ["*"]
    Condition = {
      Bool = { "g:PrincipalIsRootUser" = "true" }
    }
  }

  # RAM organization boundary
  stmt_deny_unauthorized_ram_share = {
    Sid      = "DenyRamShareToUnauthorizedOrg"
    Effect   = "Deny"
    Action   = ["ram:resourceShares:create", "ram:resourceShares:associate", "ram:resourceShares:update"]
    Resource = ["*"]
    Condition = {
      "ForAnyValue:StringNotMatch" = { "ram:TargetOrgPaths" = [local._ram_org_path] }
    }
  }

  # Config organization boundary
  stmt_deny_unauthorized_rms_aggregation = {
    Sid      = "DenyRmsAggregationFromUnauthorizedOrg"
    Effect   = "Deny"
    Action   = ["rms:aggregationAuthorizations:create"]
    Resource = ["*"]
    Condition = {
      StringNotMatch = { "rms:AuthorizedAccountOrgPath" = [local._rms_org_path] }
    }
  }

  # Mandatory tag enforcement
  # Note: Use one Deny per tag; a combined Null condition would require all tags to be absent.
  stmt_require_mandatory_tags = {
    for t in local._scps.require_mandatory_tags.mandatory_tags :
    "require_mandatory_tag_${t}" => {
      Sid      = "DenyCreateWithoutTag${replace(title(t), "/[^0-9A-Za-z]/", "")}"
      Effect   = "Deny"
      Action   = local._scps.require_mandatory_tags.actions
      Resource = ["*"]
      Condition = {
        Null = { "g:RequestTag/${t}" = "true" }
      }
    }
  }

  # Public bucket restriction
  # Note: StringEquals avoids denying private bucket requests with no ACL header.
  stmt_deny_public_obs = {
    Sid      = "DenyPublicObsUnlessExceptionTagged"
    Effect   = "Deny"
    Action   = local._scps.deny_public_obs.actions
    Resource = ["*"]
    Condition = merge(
      { StringEquals = { "obs:x-obs-acl" = local._scps.deny_public_obs.public_acls } },
      local._scps.deny_public_obs.exception_tag_key != "" ? {
        StringNotEqualsIfExists = {
          "g:ResourceTag/${local._scps.deny_public_obs.exception_tag_key}" = local._scps.deny_public_obs.exception_tag_value
        }
      } : {}
    )
  }

  # CTS tracker protection
  # Note: An empty administrator list makes protection unconditional.
  stmt_protect_cts_tracker = merge(
    {
      Sid      = "ProtectDefaultCtsTracker"
      Effect   = "Deny"
      Action   = local._scps.protect_cts_tracker.actions
      Resource = [local._scps.protect_cts_tracker.tracker_resource]
    },
    length(local._scps.protect_cts_tracker.admin_principal_urns) > 0 ? {
      Condition = { StringNotLike = { "g:PrincipalUrn" = local._scps.protect_cts_tracker.admin_principal_urns } }
    } : {}
  )

  # Allowed region enforcement
  stmt_deny_outside_allowed_region = {
    Sid      = "DenyResourceOutsideAllowedRegion"
    Effect   = "Deny"
    Action   = [for s in local._scps.deny_outside_allowed_region.services : "${s}:*:*"]
    Resource = ["*"]
    Condition = {
      StringNotEqualsIfExists = { "g:RequestedRegion" = local._scps.deny_outside_allowed_region.allowed_regions }
    }
  }

  # Approved tag keys
  # Note: Case-sensitive, multivalued g:TagKeys requires ForAnyValue:StringNotEquals.
  stmt_require_tag_keys = {
    Sid      = "DenyCreateWithUnapprovedTagKeys"
    Effect   = "Deny"
    Action   = local._scps.require_tag_keys.actions
    Resource = ["*"]
    Condition = {
      "ForAnyValue:StringNotEqualsIfExists" = { "g:TagKeys" = local._scps.require_tag_keys.tag_keys }
    }
  }

  # Enabled guardrail collection
  scp_all = merge(
    var.enable_scps && local._scps.deny_leave_org.enabled ? { deny_leave_org = { stmt = local.stmt_deny_leave_org, enforce = local._scps.deny_leave_org.enforce } } : {},
    var.enable_scps && local._scps.deny_root_user.enabled ? { deny_root_user = { stmt = local.stmt_deny_root_user, enforce = local._scps.deny_root_user.enforce } } : {},
    var.enable_scps && local._scps.deny_unauthorized_ram_share.enabled ? { deny_unauthorized_ram_share = { stmt = local.stmt_deny_unauthorized_ram_share, enforce = local._scps.deny_unauthorized_ram_share.enforce } } : {},
    var.enable_scps && local._scps.deny_unauthorized_rms_aggregation.enabled ? { deny_unauthorized_rms_aggregation = { stmt = local.stmt_deny_unauthorized_rms_aggregation, enforce = local._scps.deny_unauthorized_rms_aggregation.enforce } } : {},
    var.enable_scps && local._scps.require_mandatory_tags.enabled ? {
      for k, s in local.stmt_require_mandatory_tags :
      k => { stmt = s, enforce = local._scps.require_mandatory_tags.enforce }
    } : {},
    var.enable_scps && local._scps.deny_public_obs.enabled ? { deny_public_obs = { stmt = local.stmt_deny_public_obs, enforce = local._scps.deny_public_obs.enforce } } : {},
    var.enable_scps && local._scps.protect_cts_tracker.enabled ? { protect_cts_tracker = { stmt = local.stmt_protect_cts_tracker, enforce = local._scps.protect_cts_tracker.enforce } } : {},
    var.enable_scps && local._scps.deny_outside_allowed_region.enabled ? { deny_outside_allowed_region = { stmt = local.stmt_deny_outside_allowed_region, enforce = local._scps.deny_outside_allowed_region.enforce } } : {},
    var.enable_scps && local._scps.require_tag_keys.enabled && length(local._scps.require_tag_keys.tag_keys) > 0 ? { require_tag_keys = { stmt = local.stmt_require_tag_keys, enforce = local._scps.require_tag_keys.enforce } } : {},
  )

  # Enforced and staged policy groups
  # Note: Tag guardrails use dedicated documents named by tag_policy_name.
  _tag_scp_all  = { for k, v in local.scp_all : k => v if startswith(k, "require_") }
  _main_scp_all = { for k, v in local.scp_all : k => v if !startswith(k, "require_") }

  enforced_stmts = [for k, v in local._main_scp_all : v.stmt if v.enforce]
  staged_stmts   = [for k, v in local._main_scp_all : v.stmt if !v.enforce]

  tag_enforced_stmts = [for k, v in local._tag_scp_all : v.stmt if v.enforce]
  tag_staged_stmts   = [for k, v in local._tag_scp_all : v.stmt if !v.enforce]

  # Policy statement batching
  # Note: range and slice preserve heterogeneous tuple types.
  enforced_chunks = [
    for i in range(0, length(local.enforced_stmts), var.max_statements_per_scp) :
    slice(local.enforced_stmts, i, min(i + var.max_statements_per_scp, length(local.enforced_stmts)))
  ]
  staged_chunks = [
    for i in range(0, length(local.staged_stmts), var.max_statements_per_scp) :
    slice(local.staged_stmts, i, min(i + var.max_statements_per_scp, length(local.staged_stmts)))
  ]
  tag_enforced_chunks = [
    for i in range(0, length(local.tag_enforced_stmts), var.max_statements_per_scp) :
    slice(local.tag_enforced_stmts, i, min(i + var.max_statements_per_scp, length(local.tag_enforced_stmts)))
  ]
  tag_staged_chunks = [
    for i in range(0, length(local.tag_staged_stmts), var.max_statements_per_scp) :
    slice(local.tag_staged_stmts, i, min(i + var.max_statements_per_scp, length(local.tag_staged_stmts)))
  ]
}

# --- Enforced policies and attachments ---

resource "huaweicloud_organizations_policy" "enforced" {
  count = length(local.enforced_chunks)

  name        = "${var.policy_name}-${count.index + 1}"
  description = "Landing Zone guardrails (enforced), group ${count.index + 1}"
  type        = "service_control_policy"
  content     = jsonencode({ Version = "5.0", Statement = local.enforced_chunks[count.index] })
  tags        = var.tags
}

resource "huaweicloud_organizations_policy_attach" "enforced" {
  count = length(huaweicloud_organizations_policy.enforced)

  policy_id = huaweicloud_organizations_policy.enforced[count.index].id
  entity_id = var.attach_target_id
}

# --- Staged policies ---
# Note: Created without attachments.

resource "huaweicloud_organizations_policy" "staged" {
  count = length(local.staged_chunks)

  name        = "${var.policy_name}-staged-${count.index + 1}"
  description = "Landing Zone guardrails (staged, not attached), group ${count.index + 1}"
  type        = "service_control_policy"
  content     = jsonencode({ Version = "5.0", Statement = local.staged_chunks[count.index] })
  tags        = var.tags
}

# --- Tag governance policies ---

resource "huaweicloud_organizations_policy" "tag_enforced" {
  count = length(local.tag_enforced_chunks)

  name        = length(local.tag_enforced_chunks) > 1 ? "${var.tag_policy_name}-${count.index + 1}" : var.tag_policy_name
  description = "Landing Zone tag guardrails (enforced)"
  type        = "service_control_policy"
  content     = jsonencode({ Version = "5.0", Statement = local.tag_enforced_chunks[count.index] })
  tags        = var.tags
}

resource "huaweicloud_organizations_policy_attach" "tag_enforced" {
  count = length(huaweicloud_organizations_policy.tag_enforced)

  policy_id = huaweicloud_organizations_policy.tag_enforced[count.index].id
  entity_id = var.attach_target_id
}

resource "huaweicloud_organizations_policy" "tag_staged" {
  count = length(local.tag_staged_chunks)

  name        = length(local.tag_staged_chunks) > 1 ? "${var.tag_policy_name}-staged-${count.index + 1}" : "${var.tag_policy_name}-staged"
  description = "Landing Zone tag guardrails (staged, not attached)"
  type        = "service_control_policy"
  content     = jsonencode({ Version = "5.0", Statement = local.tag_staged_chunks[count.index] })
  tags        = var.tags
}
