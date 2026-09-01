# The 8 Landing Zone identity guardrails - authored as v5.0 SCP statements.
#
# Huawei caps attached SCPs at 5 per entity (the default FullAccess takes one),
# so the guardrails are NOT one-SCP-each. Each guardrail is a single Deny
# *statement*, and statements are packed into combined SCP documents (each well
# under the 5,120-char limit). enforce = true statements go into the attached
# (LIVE) document(s); enforce = false ones into a staged, unattached document.
#
# Statement bodies validated against the identity guardrails workbook and
# https://support.huaweicloud.com/intl/en-us/usermanual-organizations/org_03_0081.html

locals {
  _scps = var.scps

  # Allowed org path for the cross-org guardrails (#3 RAM, #4 RMS), derived from
  # foundation as '<org_id>/<root_ou_id>/*' (a policy may override via allowed_org_path).
  #
  # Both guardrails use StringNotMatch - the Huawei IAM v5 string operator where
  # '*'/'?' are real wildcards - so the trailing '*' matches every org path beneath
  # the root (and denies anything outside it). Do NOT switch these to StringNotLike:
  # that operator does case-insensitive SUBSTRING matching and does NOT treat '*' as
  # a wildcard, so a '*'-terminated path is matched literally and denies EVERY share
  # (no real ram:TargetOrgPaths contains a literal '*'). Verified working in-org with
  # StringNotMatch + '<org_id>/<root_ou_id>/*'.
  _org_path     = var.org_id != "" && var.root_ou_id != "" ? "${var.org_id}/${var.root_ou_id}/*" : ""
  _ram_org_path = local._scps.deny_unauthorized_ram_share.allowed_org_path != "" ? local._scps.deny_unauthorized_ram_share.allowed_org_path : local._org_path
  _rms_org_path = local._scps.deny_unauthorized_rms_aggregation.allowed_org_path != "" ? local._scps.deny_unauthorized_rms_aggregation.allowed_org_path : local._org_path

  # ---- Per-guardrail Deny statements (objects, combined into documents below) ----

  # 1. Deny leaving the organization.
  stmt_deny_leave_org = {
    Sid      = "DenyLeaveOrganization"
    Effect   = "Deny"
    Action   = ["organizations:organizations:leave"]
    Resource = ["*"]
  }

  # 2. Deny root user usage. Service names can't be wildcarded, so enumerate.
  # Use Bool (NOT BoolIfExists): with IfExists, an ABSENT g:PrincipalIsRootUser
  # (the case for ordinary non-root member-account users) is treated as a match,
  # so the Deny fires and blocks every enumerated service for non-root users. Bool
  # denies only when the key is explicitly "true" (the actual root user).
  stmt_deny_root_user = {
    Sid      = "DenyRootUserAllActions"
    Effect   = "Deny"
    Action   = [for s in local._scps.deny_root_user.services : "${s}:*:*"]
    Resource = ["*"]
    Condition = {
      Bool = { "g:PrincipalIsRootUser" = "true" }
    }
  }

  # 3. Deny RAM resource shares to unauthorized organizations.
  stmt_deny_unauthorized_ram_share = {
    Sid      = "DenyRamShareToUnauthorizedOrg"
    Effect   = "Deny"
    Action   = ["ram:resourceShares:create", "ram:resourceShares:associate", "ram:resourceShares:update"]
    Resource = ["*"]
    Condition = {
      "ForAnyValue:StringNotMatch" = { "ram:TargetOrgPaths" = [local._ram_org_path] }
    }
  }

  # 4. Deny RMS aggregation authorization from unauthorized organizations.
  stmt_deny_unauthorized_rms_aggregation = {
    Sid      = "DenyRmsAggregationFromUnauthorizedOrg"
    Effect   = "Deny"
    Action   = ["rms:aggregationAuthorizations:create"]
    Resource = ["*"]
    Condition = {
      StringNotMatch = { "rms:AuthorizedAccountOrgPath" = [local._rms_org_path] }
    }
  }

  # 5. Deny resource create/update without mandatory tags. ONE Deny statement PER
  # mandatory tag - NOT a single multi-key Null block.
  #
  # Huawei ANDs multiple keys within one condition operator block (org_03_0033:
  # "the policy can be applied only when all the conditions are met"), so a single
  # Null block listing all tags would deny only when EVERY tag is absent - a
  # partially-tagged create (e.g. just `bu`) would slip through. Separate Deny
  # statements are OR-ed at the policy level, so a deny fires if ANY one tag is
  # missing. Null = "key is absent"; it takes NO qualifier - `ForAnyValue:Null`
  # (the old, stale deployed form) is invalid, and IfExists is not allowed on Null.
  # Produces a map of { key => statement } spread into scp_all below.
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

  # 6. Deny public OBS unless exception-tagged. exception_tag_key = "" => no exception.
  # Use StringEquals (NOT StringEqualsIfExists) on obs:x-obs-acl: with IfExists, a
  # bucket create that doesn't send an x-obs-acl header (a normal PRIVATE bucket)
  # has the key ABSENT, which IfExists treats as a match - so it wrongly denies all
  # private bucket creation. StringEquals denies only when the ACL is explicitly
  # public.
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

  # 7. Protect the default CTS tracker. admin_principal_urns = [] => unconditional
  # (the Condition key is omitted entirely).
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

  # 8. Deny resource creation outside the allowed region(s). Enumerate services.
  stmt_deny_outside_allowed_region = {
    Sid      = "DenyResourceOutsideAllowedRegion"
    Effect   = "Deny"
    Action   = [for s in local._scps.deny_outside_allowed_region.services : "${s}:*:*"]
    Resource = ["*"]
    Condition = {
      StringNotEqualsIfExists = { "g:RequestedRegion" = local._scps.deny_outside_allowed_region.allowed_regions }
    }
  }

  # 9. Deny create actions unless the request carries approved tag keys. Actions
  # are enumerated (no wildcard service). g:TagKeys is CASE-SENSITIVE - tag_keys
  # are passed through exactly as entered in the sheet-01 TagPolicies.
  # g:TagKeys is multi-valued, so a ForAllValues/ForAnyValue qualifier is REQUIRED
  # (MISSING_QUALIFIER otherwise). ForAnyValue:StringNotEquals = deny if ANY request
  # tag key is outside the approved set (an allowlist of tag keys).
  stmt_require_tag_keys = {
    Sid      = "DenyCreateWithUnapprovedTagKeys"
    Effect   = "Deny"
    Action   = local._scps.require_tag_keys.actions
    Resource = ["*"]
    Condition = {
      "ForAnyValue:StringNotEqualsIfExists" = { "g:TagKeys" = local._scps.require_tag_keys.tag_keys }
    }
  }

  # Assemble enabled guardrails into { key => { stmt, enforce } }. Built
  # explicitly per policy because var.scps is an object (no dynamic key indexing).
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

  # Huawei caps attached SCPs at 5 per entity (the default FullAccess takes one),
  # so guardrails are packed into combined documents rather than one-SCP-each.
  # enforce = true statements go into the attached (LIVE) document(s); enforce =
  # false ones into a staged, unattached document. Each document holds up to
  # max_statements_per_scp statements and stays under the 5,120-char limit.
  #
  # The tag-governance guardrails (the `require_*` keys - the per-tag mandatory-tag
  # statements and require_tag_keys) are grouped into their OWN dedicated document
  # (var.tag_policy_name) so the tag policy is self-contained and separately named;
  # every other guardrail goes into the general var.policy_name document(s).
  _tag_scp_all  = { for k, v in local.scp_all : k => v if startswith(k, "require_") }
  _main_scp_all = { for k, v in local.scp_all : k => v if !startswith(k, "require_") }

  enforced_stmts = [for k, v in local._main_scp_all : v.stmt if v.enforce]
  staged_stmts   = [for k, v in local._main_scp_all : v.stmt if !v.enforce]

  tag_enforced_stmts = [for k, v in local._tag_scp_all : v.stmt if v.enforce]
  tag_staged_stmts   = [for k, v in local._tag_scp_all : v.stmt if !v.enforce]

  # NB: chunklist() can't be used here - the statement objects are heterogeneous
  # (some carry a Condition, some don't), so they form a tuple, not a list.
  # range()+slice() chunk a tuple while preserving the per-element types.
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

# ---- Enforced (LIVE) - combined SCP document(s), attached at attach_target_id. ----

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

# ---- Staged (INERT) - combined SCP document(s), created but NOT attached. ----

resource "huaweicloud_organizations_policy" "staged" {
  count = length(local.staged_chunks)

  name        = "${var.policy_name}-staged-${count.index + 1}"
  description = "Landing Zone guardrails (staged, not attached), group ${count.index + 1}"
  type        = "service_control_policy"
  content     = jsonencode({ Version = "5.0", Statement = local.staged_chunks[count.index] })
  tags        = var.tags
}

# Tag guardrails - dedicated SCP document(s) for the tag-governance policies
# (mandatory tags + approved tag keys). Named var.tag_policy_name (no numeric
# suffix unless they overflow a single document). Enforced ones are attached.

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
