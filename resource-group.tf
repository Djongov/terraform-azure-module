resource "azurerm_resource_group" "this" {
  name     = lower("${var.project_name}-rg-${var.environment}-${local.location_abbreviation}")
  location = var.location

  tags = local.common_tags
}