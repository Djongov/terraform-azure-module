resource "azurerm_app_service_certificate_order" "this" {
  for_each = var.app_service_certificates != null ? var.app_service_certificates : {}

  name                = each.key
  resource_group_name = azurerm_resource_group.this.name
  location            = "global"
  distinguished_name  = each.value.dns_name
  product_type        = each.value.product_type
  auto_renew          = try(each.value.auto_renew, null)        # default to true
  key_size            = try(each.value.key_size, null)          # default to 2048
  validity_in_years   = try(each.value.validity_in_years, null) # default to 1

  tags = local.common_tags
}
