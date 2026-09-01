# ---- Basic Anti-DDoS (per-EIP traffic-cleaning threshold + optional SMN alarm) ----

# Resolve alarm-topic NAMES to URNs (one lookup per distinct topic).
data "huaweicloud_smn_topics" "alarm" {
  for_each = toset([for a in var.antiddos : a.alarm_topic if a.alarm_topic != ""])

  name = each.value

  lifecycle {
    postcondition {
      condition     = length(self.topics) > 0
      error_message = "SMN topic '${each.value}' not found in this account. 06-observability creates the alarm topics - apply 06 first, or fix the AntiDDoS AlarmTopic name."
    }
  }
}

resource "huaweicloud_antiddos_basic" "this" {
  for_each = { for a in var.antiddos : a.name => a }

  eip_id            = var.eip_ids[each.value.eip]
  traffic_threshold = each.value.threshold_mbps
  topic_urn         = each.value.alarm_topic != "" ? data.huaweicloud_smn_topics.alarm[each.value.alarm_topic].topics[0].topic_urn : null
}

# ---- Dedicated WAF instance + shared policy + protected domains ----

# Auto-select the engine ECS flavor when not pinned: professional needs 2U4G,
# enterprise needs 8U16G (provider docs requirement).
data "huaweicloud_compute_flavors" "waf" {
  count = var.enable_waf && var.waf_ecs_flavor == "" ? 1 : 0

  availability_zone = var.waf_availability_zone
  performance_type  = "normal"
  cpu_core_count    = var.waf_specification_code == "waf.instance.enterprise" ? 8 : 2
  memory_size       = var.waf_specification_code == "waf.instance.enterprise" ? 16 : 4
}

# Own security group when none is supplied: WAF terminates HTTP/S and forwards
# to the origin, so 80/443 in + all out covers the engine.
resource "huaweicloud_networking_secgroup" "waf" {
  count = var.enable_waf && length(var.waf_security_group_ids) == 0 ? 1 : 0

  name        = "${var.waf_instance_name}-sg"
  description = "WAF dedicated engine: HTTP/HTTPS in, all out"
}

resource "huaweicloud_networking_secgroup_rule" "waf_ingress" {
  for_each = var.enable_waf && length(var.waf_security_group_ids) == 0 ? toset(["80", "443"]) : toset([])

  security_group_id = huaweicloud_networking_secgroup.waf[0].id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  ports             = each.value
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "huaweicloud_networking_secgroup_rule" "waf_egress" {
  count = var.enable_waf && length(var.waf_security_group_ids) == 0 ? 1 : 0

  security_group_id = huaweicloud_networking_secgroup.waf[0].id
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "huaweicloud_waf_dedicated_instance" "this" {
  count = var.enable_waf ? 1 : 0

  name                  = var.waf_instance_name
  available_zone        = var.waf_availability_zone
  specification_code    = var.waf_specification_code
  ecs_flavor            = var.waf_ecs_flavor != "" ? var.waf_ecs_flavor : data.huaweicloud_compute_flavors.waf[0].flavors[0].id
  vpc_id                = var.waf_vpc_id
  subnet_id             = var.waf_subnet_id
  security_group        = length(var.waf_security_group_ids) > 0 ? var.waf_security_group_ids : [huaweicloud_networking_secgroup.waf[0].id]
  enterprise_project_id = var.enterprise_project_id

  tags = var.tags
}

resource "huaweicloud_waf_policy" "this" {
  count = var.enable_waf ? 1 : 0

  name                  = var.waf_policy_name
  enterprise_project_id = var.enterprise_project_id

  # The dedicated domains only take effect once the instance exists.
  depends_on = [huaweicloud_waf_dedicated_instance.this]
}

resource "huaweicloud_waf_dedicated_domain" "this" {
  for_each = var.enable_waf ? { for d in var.waf_domains : d.domain => d } : {}

  domain                = each.value.domain
  policy_id             = huaweicloud_waf_policy.this[0].id
  certificate_id        = each.value.certificate_id != "" ? each.value.certificate_id : null
  protect_status        = 1
  enterprise_project_id = var.enterprise_project_id

  server {
    client_protocol = each.value.client_protocol
    server_protocol = each.value.server_protocol
    address         = each.value.origin_address
    port            = each.value.origin_port
    type            = "ipv4"
    vpc_id          = var.waf_vpc_id
  }

  depends_on = [huaweicloud_waf_dedicated_instance.this]
}
