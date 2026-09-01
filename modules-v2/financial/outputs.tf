output "cost_center_ep_ids" {
  description = "Map of cost-center EP name -> EP ID"
  value       = { for k, v in huaweicloud_enterprise_project.cost_centers : k => v.id }
}
