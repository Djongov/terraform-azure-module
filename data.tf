data "azurerm_client_config" "current" {}

data "azurerm_container_registry" "linux_webapp_acr" {
  for_each = var.web_apps != null && var.app_service_plans != null ? {
    for k, v in var.web_apps : k => v
    if lookup(v.application_stack, "acr_id", null) != null &&
    lookup(v.application_stack, "acr_location", null) == null
  } : {}
  name                = split("/", each.value.application_stack.acr_id)[8]
  resource_group_name = split("/", each.value.application_stack.acr_id)[4]
}