# Config (RMS) conformance packs - org-wide DETECTIVE compliance. Deployed as
# huaweicloud_rms_organizational_assignment_package at the org (organization_id),
# evaluated across every member except excluded_accounts. Runs in the Config
# admin account alongside the recorder + aggregator (gated by enable_config).
#
# template_key is tenant/region-specific, so it is NOT hard-coded. It is resolved
# at plan time from the live templates data source by matching the readable pack
# name against the available template keys; a spec-supplied template_key overrides
# the match. If a name can't be resolved, the precondition fails and lists the
# available keys so the operator can set one explicitly.

data "huaweicloud_rms_assignment_package_templates" "all" {
  count = var.enable_config && length(var.conformance_packs) > 0 ? 1 : 0
}

locals {
  _templates      = try(data.huaweicloud_rms_assignment_package_templates.all[0].templates, [])
  _available_keys = local._templates[*].template_key

  # Normalize to lowercase alphanumerics for fuzzy name->key matching.
  _enabled_packs = [for p in var.conformance_packs : p if p.enabled]

  conformance_resolved = {
    for p in local._enabled_packs : p.name => {
      excluded_accounts = p.excluded_accounts
      vars              = p.vars
      pack_name         = p.pack_name != "" ? p.pack_name : replace(lower(p.name), "/[^a-z0-9-]+/", "-")
      template_key = p.template_key != "" ? p.template_key : try(one([
        for t in local._templates : t.template_key
        if strcontains(
          lower(replace(t.template_key, "/[^a-zA-Z0-9]/", "")),
          lower(replace(p.name, "/[^a-zA-Z0-9]/", ""))
        )
      ]), null)
    }
  }
}

# Per-pack template detail - returns the template's parameters and body.
# Filtered by template_key because the list data source above doesn't reliably
# populate parameters. Used to build vars_structure below.
data "huaweicloud_rms_assignment_package_templates" "detail" {
  for_each     = { for k, v in local.conformance_resolved : k => v if v.template_key != null }
  template_key = each.value.template_key
}

locals {
  # Parameter defaults per pack, taken from the template BODY (the parameters
  # listing is lossy); spec-supplied Vars override individual parameters.
  _tpl_var_defaults = {
    for k, d in data.huaweicloud_rms_assignment_package_templates.detail :
    k => {
      for name, defs in try(jsondecode(d.templates[0].template_body).variable, {}) :
      name => jsonencode(try(defs[0].default, defs.default))
    }
  }

  # Fallback for templates whose body isn't parseable: the parameters listing,
  # with typed empty JSON synthesized for its lossy "" defaults.
  _pack_var_values = {
    for k in keys(data.huaweicloud_rms_assignment_package_templates.detail) :
    k => (
      length(local._tpl_var_defaults[k]) > 0 ? local._tpl_var_defaults[k] : {
        for p in try(data.huaweicloud_rms_assignment_package_templates.detail[k].templates[0].parameters, []) :
        p.name => (p.default_value != "" ? p.default_value : (p.type == "Array" ? "[]" : jsonencode("")))
      }
    )
  }
}

resource "huaweicloud_rms_organizational_assignment_package" "this" {
  for_each = var.enable_config ? local.conformance_resolved : {}

  organization_id   = var.org_id
  name              = each.value.pack_name
  template_key      = each.value.template_key
  excluded_accounts = length(each.value.excluded_accounts) > 0 ? each.value.excluded_accounts : null

  # The org assignment package requires every template parameter explicitly;
  # values come from the template body's defaults plus spec overrides.
  dynamic "vars_structure" {
    for_each = try(local._pack_var_values[each.key], {})
    content {
      var_key   = vars_structure.key
      var_value = lookup(each.value.vars, vars_structure.key, vars_structure.value)
    }
  }

  # Org conformance packs require an enabled resource recorder in this
  # account, so the module also creates the recorder.
  depends_on = [huaweicloud_rms_resource_recorder.this]

  lifecycle {
    precondition {
      condition     = each.value.template_key != null
      error_message = "Could not resolve a template_key for conformance pack '${each.key}' (ambiguous or no name match). Set TemplateKey explicitly in the spec. Available keys: ${join(", ", local._available_keys)}."
    }
  }
}
