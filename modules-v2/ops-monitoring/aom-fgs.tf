# AOM + FGS - both deferred Day-1 (gated by enable_aom / enable_fgs).
# Scaffolding only. Extend per modules-day1-resources.md section Module 7 deferred.

# ---- AOM placeholder ----

# resource "huaweicloud_aom_alarm_rule" "this" {
#   count = var.enable_aom ? 1 : 0
#   ...
# }

# Additional AOM resources (when enable_aom = true):
#   huaweicloud_aom_alarm_policy, _alarm_action_rule, _alarm_group_rule,
#   _alarm_inhibit_rule, _alarm_silence_rule, _alarm_rules_template,
#   _event_alarm_rule, _message_template,
#   _dashboard, _dashboards_folder,
#   _cmdb_application, _cmdb_component, _cmdb_environment,
#   _service_discovery_rule,
#   _prom_instance, _prometheus_instance, _recording_rule,
#   _cloud_service_access, _multi_account_aggregation_rule

# ---- FGS placeholder ----

# resource "huaweicloud_fgs_function" "remediation" {
#   count = var.enable_fgs ? 1 : 0
#   ...
# }

# Additional FGS resources (when enable_fgs = true):
#   huaweicloud_fgs_function_trigger, _async_invoke_configuration,
#   _async_log_configuration, _lts_log_enable,
#   _function_tracing_configuration, _dependency, _dependency_version,
#   _application, _vpc_endpoint
