# LTS infrastructure - the single CTS log group + stream for the org CTS trail.
# Names support {account-name} (substituted in main.tf locals).

resource "huaweicloud_lts_group" "cts" {
  group_name  = local.cts_log_group_name
  ttl_in_days = var.lts_hot_retention_days
  tags        = var.tags
}

resource "huaweicloud_lts_stream" "cts" {
  group_id    = huaweicloud_lts_group.cts.id
  stream_name = local.cts_log_stream_name
  ttl_in_days = var.lts_hot_retention_days
  tags        = var.tags
}
