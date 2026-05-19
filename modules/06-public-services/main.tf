locals {
  tags = merge({
    ManagedBy = "terraform"
    Project   = "landing-zone"
    Layer     = "public-services"
  }, var.tags)
}

# ── Shared ELB ────────────────────────────────────────────────────────────────

resource "huaweicloud_elb_loadbalancer" "shared" {
  name              = var.elb_name
  description       = "Landing zone shared ingress load balancer"
  vpc_id            = var.vpc_id
  ipv4_subnet_id    = var.subnet_id
  availability_zones = var.elb_availability_zones
  region            = var.home_region
  tags              = local.tags
}

resource "huaweicloud_elb_listener" "https" {
  name            = "${var.elb_name}-https"
  protocol        = "HTTPS"
  protocol_port   = 443
  loadbalancer_id = huaweicloud_elb_loadbalancer.shared.id
  region          = var.home_region

  idle_timeout       = 60
  request_timeout    = 60
  response_timeout   = 60
}

resource "huaweicloud_elb_listener" "http_redirect" {
  name            = "${var.elb_name}-http-redirect"
  protocol        = "HTTP"
  protocol_port   = 80
  loadbalancer_id = huaweicloud_elb_loadbalancer.shared.id
  region          = var.home_region
}

resource "huaweicloud_elb_l7rule" "redirect" {
  listener_id  = huaweicloud_elb_listener.http_redirect.id
  type         = "HOST_NAME"
  compare_type = "STARTS_WITH"
  value        = "."
  region       = var.home_region
}

# ── WAF Dedicated Instance ────────────────────────────────────────────────────

resource "huaweicloud_waf_dedicated_instance" "this" {
  count = var.enable_waf ? 1 : 0

  name               = var.waf_name
  available_zone     = "${var.home_region}a"
  specification_code = var.waf_specification_code
  vpc_id             = var.vpc_id
  subnet_id          = var.subnet_id
  security_group     = []
  region             = var.home_region
}

resource "huaweicloud_waf_policy" "default" {
  count = var.enable_waf ? 1 : 0

  name   = "lz-default-waf-policy"
  region = var.home_region

  options {
    basic_web_protection  = true
    general_check         = true
    crawler_engine        = true
    crawler_scanner       = true
    crawler_script        = true
    cc_attack_protection  = true
    precise_protection    = true
    blacklist             = true
    data_masking          = true
    anti_tamper           = true
    geolocation_access_control = false
    known_attack_source   = true
    anti_crawler          = true
  }
}

# ── Public DNS Zones ──────────────────────────────────────────────────────────

resource "huaweicloud_dns_zone" "public" {
  for_each = { for z in var.public_dns_zones : z.name => z }

  name        = each.value.name
  description = each.value.description
  email       = each.value.email
  zone_type   = "public"
  region      = var.home_region
  tags        = local.tags
}

# ── Private DNS Zones ─────────────────────────────────────────────────────────

resource "huaweicloud_dns_zone" "private" {
  for_each = { for z in var.private_dns_zones : z.name => z }

  name        = each.value.name
  description = each.value.description
  zone_type   = "private"
  region      = var.home_region
  tags        = local.tags

  router {
    router_id     = each.value.associated_vpc_id
    router_region = var.home_region
  }
}

# ── DNS resolver endpoint ─────────────────────────────────────────────────────

resource "huaweicloud_dns_endpoint" "inbound" {
  name      = "lz-dns-inbound"
  direction = "inbound"
  region    = var.home_region

  ip_addresses {
    subnet_id = var.subnet_id
  }

  ip_addresses {
    subnet_id = var.subnet_id
  }
}
