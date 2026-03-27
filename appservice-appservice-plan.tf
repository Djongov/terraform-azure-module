resource "azurerm_service_plan" "this" {
  for_each = var.app_service_plans != null ? {
    for k, v in var.app_service_plans : k => v
  } : {}

  name                     = each.value.name != null ? each.value.name : each.value.key != null ? lower("${var.project_name}-${each.value.key}-farm-${var.environment}-${local.location_abbreviation_app_service_plan[each.key]}") : lower("${var.project_name}-farm-${var.environment}-${local.location_abbreviation_app_service_plan[each.key]}")
  location                 = each.value.location != null ? each.value.location : azurerm_resource_group.this.location
  resource_group_name      = azurerm_resource_group.this.name
  os_type                  = each.value.os_type
  sku_name                 = each.value.sku
  worker_count             = each.value.worker_count != null ? each.value.worker_count : null
  zone_balancing_enabled   = each.value.zone_balancing_enabled != null ? each.value.zone_balancing_enabled : false
  per_site_scaling_enabled = each.value.per_site_scaling_enabled != null ? each.value.per_site_scaling_enabled : false
  tags = merge(
    local.common_tags,
    each.value.tags != null ? each.value.tags : {}
  )
  lifecycle {
    ignore_changes = [
      #worker_count
    ]
  }
}
