# --- Organization conformance packs ---
# Note: Template keys resolve by name unless explicitly supplied.

data "huaweicloud_rms_assignment_package_templates" "all" {
  count = var.enable_config && length(var.conformance_packs) > 0 ? 1 : 0
}

locals {
  _templates      = try(data.huaweicloud_rms_assignment_package_templates.all[0].templates, [])
  _available_keys = local._templates[*].template_key

  # Template name normalization
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

# --- Conformance template lookup ---
data "huaweicloud_rms_assignment_package_templates" "detail" {
  for_each     = { for k, v in local.conformance_resolved : k => v if v.template_key != null }
  template_key = each.value.template_key
}

locals {
  # Template parameter defaults
  _tpl_var_defaults = {
    for k, d in data.huaweicloud_rms_assignment_package_templates.detail :
    k => {
      for name, defs in try(jsondecode(d.templates[0].template_body).variable, {}) :
      name => jsonencode(try(defs[0].default, defs.default))
    }
  }

  # Parameter-list fallback
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

  # Complete template parameters
  # Note: Every template parameter is passed explicitly, including defaults.
  dynamic "vars_structure" {
    for_each = try(local._pack_var_values[each.key], {})
    content {
      var_key   = vars_structure.key
      var_value = lookup(each.value.vars, vars_structure.key, vars_structure.value)
    }
  }

  # Note: Enable the account recorder before creating organization packs.
  depends_on = [huaweicloud_rms_resource_recorder.this]

  lifecycle {
    precondition {
      condition     = each.value.template_key != null
      error_message = "Could not resolve a template_key for conformance pack '${each.key}' (ambiguous or no name match). Set TemplateKey explicitly in the spec. Available keys: ${join(", ", local._available_keys)}."
    }
  }
}
