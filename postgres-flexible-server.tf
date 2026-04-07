locals {
  # PostgreSQL Flexible Servers databases
  postgresql_databases = {
    for db in flatten([
      for servers_key, servers in var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {} : [
        for database_key, databases in servers.databases : {
          server           = servers_key
          database         = database_key
          database_details = databases
        }
      ]
    ]) : "${db.server}-${db.database}" => db
  }

  # PostgreSQL Flexible Servers firewall rules
  postgresql_firewall_rules = flatten([
    for servers_key, servers in var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {} : [
      for rule_key, rule in servers.firewall_rules != null ? servers.firewall_rules : {} : {
        server   = servers_key
        rule_key = rule_key
        rule     = rule
      }
    ]
  ])

  # Map each PostgreSQL server to its referenced web app's outbound IPs
  postgresql_webapp_firewall_rules = {
    for postgresql_key, postgresql_val in var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {} :
    postgresql_key => {
      webapp_key = postgresql_val.allow_firewall_webapp
      ips        = lookup(azurerm_linux_web_app.this[postgresql_val.allow_firewall_webapp], "possible_outbound_ip_address_list", [])
    }
    if postgresql_val.allow_firewall_webapp != null
  }

  # # Flattened webapp firewall rules for PostgreSQL
  postgresql_webapp_firewall_rule_map = {
    for rule in flatten([
      for postgresql_key, info in local.postgresql_webapp_firewall_rules : [
        for ip in info.ips : {
          webapp_key     = info.webapp_key
          postgresql_key = postgresql_key
          ip             = ip
        }
      ]
    ]) : "allow-webapp-${rule.webapp_key}-${replace(rule.ip, ".", "-")}" => rule
  }

  # Map PostgreSQL servers to their private endpoint subnet IDs
  # postgresql_private_endpoint_subnet_ids = {
  #   for k, v in coalesce(var.postgresql_flexible_servers, {}) :
  #   k => (
  #     v.subnet_id != null ? v.subnet_id :
  #     v.subnet_key != null && contains(keys(local.vnet_subnet_resources_map), v.subnet_key)
  #     ? local.vnet_subnet_resources_map[v.subnet_key].id
  #     : null
  #   )
  # }

  # # Map of subnet resources created by azurerm_subnet.vnet_subnets or empty if no vnet
  # vnet_subnet_resources_map = var.vnet != null ? azurerm_subnet.vnet_subnets : {}

  # flattened diagnostic settings
  postgresql_diagnostic_settings = merge([
    for postgres_server_key, postgres_server_value in var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {} : {
      for diag_key, diag in postgres_server_value.diagnostic_settings != null ? postgres_server_value.diagnostic_settings : {} :
      "${postgres_server_key}-${diag_key}" => {
        server                         = postgres_server_key
        key                            = diag_key
        name                           = diag.name
        log_analytics_workspace_id     = diag.log_analytics_workspace_id
        storage_account_id             = diag.storage_account_id
        eventhub_namespace             = diag.eventhub_namespace
        eventhub_authorization_rule_id = diag.eventhub_authorization_rule_id
        log_categories                 = diag.log_categories
      }
    }
  ]...)
}

resource "random_password" "postgresql_server" {
  for_each = var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {}

  length           = 20
  lower            = true
  upper            = true
  numeric          = true
  special          = true
  override_special = "!#$%"
}

resource "random_password" "postgresql_server_wo" {
  for_each = {
    for k, v in var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {} :
    k => v if v.administrator_password_wo != null && try(v.create_mode != "Default", false)
  }

  length           = 20
  lower            = true
  upper            = true
  numeric          = true
  special          = true
  override_special = "!#$%"
}


resource "azurerm_postgresql_flexible_server" "this" {
  for_each = var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {}

  name                = each.value.name != null ? each.value.name : lower("${var.project_name}-${each.key}-${var.environment}-${local.location_abbreviation}")
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  administrator_login = each.value.administrator_login

  administrator_password = random_password.postgresql_server[each.key].result

  administrator_password_wo = (
    each.value.administrator_password_wo != null
  ) ? try(random_password.postgresql_server_wo[each.key].result, null) : null

  administrator_password_wo_version = (
    each.value.administrator_password_wo_version != null
  ) ? each.value.administrator_password_wo_version : null

  version = each.value.version

  zone = each.value.zone != null ? each.value.zone : null

  sku_name = each.value.sku_name

  storage_mb = each.value.storage_mb

  storage_tier = each.value.storage_tier != null ? each.value.storage_tier : null

  public_network_access_enabled = each.value.public_network_access_enabled != null ? each.value.public_network_access_enabled : true

  auto_grow_enabled = each.value.auto_grow_enabled != null ? each.value.auto_grow_enabled : null

  backup_retention_days = each.value.backup_retention_days != null ? each.value.backup_retention_days : 7

  create_mode = each.value.create_mode != null ? each.value.create_mode : "Default"

  geo_redundant_backup_enabled = each.value.geo_redundant_backup_enabled != null ? each.value.geo_redundant_backup_enabled : null

  authentication {
    password_auth_enabled         = each.value.password_auth_enabled != null ? each.value.password_auth_enabled : true
    active_directory_auth_enabled = each.value.active_directory_auth_enabled != null ? each.value.active_directory_auth_enabled : false
    tenant_id                     = each.value.active_directory_auth_enabled != null ? data.azurerm_client_config.current.tenant_id : null
  }

  dynamic "identity" {
    for_each = each.value.identity != null ? [1] : []

    content {
      type = each.value.identity.type

      identity_ids = each.value.identity.type == "UserAssigned" ? (
        each.value.identity.identity_ids != null ? each.value.identity.identity_ids : [azurerm_user_assigned_identity.pg[each.key].id]
      ) : []
    }
  }

  dynamic "high_availability" {
    for_each = each.value.high_availability != null ? [1] : []

    content {
      mode                      = each.value.high_availability.mode
      standby_availability_zone = each.value.high_availability.standby_availability_zone != null ? each.value.high_availability.standby_availability_zone : null
    }
  }

  tags = merge(
    local.common_tags,
    each.value.tags != null ? each.value.tags : {}
  )

  depends_on = [random_password.postgresql_server, random_password.postgresql_server_wo]
}

resource "azurerm_key_vault_secret" "postgres_password" {
  for_each = var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {}

  name         = "${var.project_name}-${each.key}-${var.environment}-${local.location_abbreviation}-password"
  value        = random_password.postgresql_server[each.key].result
  key_vault_id = each.value.key_vault_id != null ? each.value.key_vault_id : azurerm_key_vault.this[each.value.key_vault_key].id

  depends_on = [azurerm_postgresql_flexible_server.this]
}

resource "azurerm_user_assigned_identity" "pg" {
  for_each = {
    for k, v in var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {} :
    k => v if try(v.identity.type == "UserAssigned" && v.identity.identity_ids == null, false)
  }

  name                = "${var.project_name}-${each.key}-pg-uami-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
}


# resource "azurerm_private_endpoint" "postgres" {
#   for_each = {
#     for k, v in var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {} :
#     k => v if(v.subnet_key != null || v.subnet_id != null) && local.postgresql_private_endpoint_subnet_ids[k] != null
#   }

#   name                          = "${azurerm_postgresql_flexible_server.this[each.key].name}-pe"
#   resource_group_name           = azurerm_resource_group.this.name
#   location                      = azurerm_resource_group.this.location
#   subnet_id                     = local.postgresql_private_endpoint_subnet_ids[each.key]
#   custom_network_interface_name = "${azurerm_postgresql_flexible_server.this[each.key].name}-pe-nic"

#   private_service_connection {
#     name                           = "${azurerm_postgresql_flexible_server.this[each.key].name}-psc"
#     private_connection_resource_id = azurerm_postgresql_flexible_server.this[each.key].id
#     subresource_names              = ["postgresqlServer"]
#     is_manual_connection           = false
#   }

#   private_dns_zone_group {
#     name = "${each.key}-dns-zone-group"
#     private_dns_zone_ids = [
#       each.value.subnet_key != null ? data.azurerm_private_dns_zone.postgres[0].id : null
#     ]
#   }

#   tags = local.common_tags
# }

# data "azurerm_virtual_network" "postgres_vnet" {
#   count = length([
#     for k, v in var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {} :
#     k if v.subnet_id != null && local.postgresql_private_endpoint_subnet_ids[k] != null
#   ]) > 0 && var.vnet != null ? 1 : 0

#   name = split("/", local.postgresql_private_endpoint_subnet_ids[values([
#     for k, v in var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {} :
#     k if v.subnet_id != null && local.postgresql_private_endpoint_subnet_ids[k] != null
#   ])[0]])[4]
#   resource_group_name = split("/", local.postgresql_private_endpoint_subnet_ids[values([
#     for k, v in var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {} :
#     k if v.subnet_id != null && local.postgresql_private_endpoint_subnet_ids[k] != null
#   ])[0]])[3]
# }

# resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
#   count = length([
#     for k, v in var.postgresql_flexible_servers != null ? var.postgresql_flexible_servers : {} :
#     k if(v.subnet_key != null || v.subnet_id != null) && local.postgresql_private_endpoint_subnet_ids[k] != null
#   ]) > 0 && var.vnet != null ? 1 : 0

#   name                  = "${var.project_name}-${var.environment}-postgres-vnet-link"
#   resource_group_name   = data.azurerm_private_dns_zone.postgres[0].resource_group_name # For some reason, the vnet link should be in the private DNS zone RG and not in the RG of the VNET. Go figure...
#   private_dns_zone_name = data.azurerm_private_dns_zone.postgres[0].name
#   virtual_network_id    = azurerm_virtual_network.this[0].id != null ? azurerm_virtual_network.this[0].id : data.azurerm_virtual_network.postgres_vnet[0].id
#   registration_enabled  = false

#   tags = local.common_tags
# }

# PostgreSQL Flexible Database resources
resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each = local.postgresql_databases

  name      = each.value.database_details.name != null ? each.value.database_details.name : each.value.database
  charset   = each.value.database_details.charset
  collation = each.value.database_details.collation
  server_id = azurerm_postgresql_flexible_server.this[each.value.server].id
}

# PostgreSQL Flexible Server Firewall Rules
resource "azurerm_postgresql_flexible_server_firewall_rule" "this" {
  for_each = {
    for item in local.postgresql_firewall_rules : "${item.server}-${item.rule_key}" => item
  }

  name             = each.value.rule.name != null ? each.value.rule.name : "${replace(each.value.rule_key, "\\.", "_")}"
  server_id        = azurerm_postgresql_flexible_server.this[each.value.server].id
  start_ip_address = each.value.rule.start_ip_address
  end_ip_address   = each.value.rule.end_ip_address
}

# PostgreSQL Flexible Server Firewall Rules for Web Apps
resource "azurerm_postgresql_flexible_server_firewall_rule" "linux_webapp" {
  for_each = local.postgresql_webapp_firewall_rule_map

  name             = each.key
  server_id        = azurerm_postgresql_flexible_server.this[each.value.postgresql_key].id
  start_ip_address = each.value.ip
  end_ip_address   = each.value.ip

  depends_on = [azurerm_linux_web_app.this]
}

# PostgreSQL Monitoring Diagnostic Settings
resource "azurerm_monitor_diagnostic_setting" "postgresql_diagnostic" {
  for_each = local.postgresql_diagnostic_settings

  name               = each.value.name != null ? each.value.name : "${var.project_name}-${each.value.server}-${var.environment}-${local.location_abbreviation}-${each.value.key}-diagnostic"
  target_resource_id = azurerm_postgresql_flexible_server.this[each.value.server].id

  log_analytics_workspace_id     = coalesce(each.value.log_analytics_workspace_id, null)
  storage_account_id             = each.value.storage_account_id
  eventhub_name                  = each.value.eventhub_namespace
  eventhub_authorization_rule_id = each.value.eventhub_authorization_rule_id

  dynamic "enabled_log" {
    for_each = {
      for cat, enabled in each.value.log_categories :
      cat => enabled
      if enabled == true && cat != "AllMetrics"
    }
    content {
      category = enabled_log.key
    }
  }

  dynamic "enabled_metric" {
    for_each = try(each.value.log_categories.AllMetrics, false) ? ["AllMetrics"] : []
    content {
      category = enabled_metric.value
    }
  }

  depends_on = [azurerm_postgresql_flexible_server.this]
}