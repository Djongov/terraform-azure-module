locals {
  flattened_custom_domains = {
    for d in flatten([
      for app_key, app in var.static_web_apps != null ? var.static_web_apps : {} : [
        for domain in coalesce(app.custom_domains, []) : {
          app_key         = app_key
          domain_name     = domain.domain_name
          validation_type = domain.validation_type
        }
      ]
    ]) :
    "${d.app_key}-${d.domain_name}" => d
  }
}

resource "azurerm_static_web_app" "this" {
  for_each = var.static_web_apps != null ? var.static_web_apps : {}

  name                = "${var.project_name}-${each.key}-${var.environment}"
  resource_group_name = each.value.resource_group_name != null ? each.value.resource_group_name : azurerm_resource_group.this.name
  location            = each.value.location != null ? each.value.location : azurerm_resource_group.this.location

  configuration_file_changes_enabled = each.value.configuration_file_changes_enabled != null ? each.value.configuration_file_changes_enabled : null
  preview_environments_enabled       = each.value.preview_environments_enabled != null ? each.value.preview_environments_enabled : null
  public_network_access_enabled      = each.value.public_network_access_enabled != null ? each.value.public_network_access_enabled : null

  sku_tier = each.value.sku

  sku_size = each.value.sku

  dynamic "identity" {
    for_each = each.value.identity != null ? [each.value.identity] : []
    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids != null ? identity.value.identity_ids : null
    }
  }

  tags = merge(
    local.common_tags,
    each.value.tags != null ? each.value.tags : {}
  )

  lifecycle {
    ignore_changes = [
      repository_url,
      repository_branch,
      repository_token,
    ]
  }
}

resource "azurerm_static_web_app_custom_domain" "this" {
  for_each = local.flattened_custom_domains

  static_web_app_id = azurerm_static_web_app.this[each.value.app_key].id
  domain_name       = each.value.domain_name
  validation_type   = each.value.validation_type
}