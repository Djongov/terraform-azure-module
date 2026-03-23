locals {
  storage_accounts_with_private_endpoint = var.storage_accounts != null ? tomap({
    for k, v in var.storage_accounts :
    k => v if v.private_endpoint != null
  }) : {}

  flattened_containers = var.storage_accounts != null ? flatten([
    for k, v in var.storage_accounts :
    v.containers != null ? [
      for container_key, container_value in v.containers : {
        storage_account = k
        name            = container_key
        access_type     = container_value.access_type
        metadata        = container_value.metadata != null ? container_value.metadata : {}
      }
    ] : []
  ]) : []

  flattened_file_shares = var.storage_accounts != null ? flatten([
    for k, v in var.storage_accounts :
    v.file_shares != null ? [
      for file_share_key, file_share_value in v.file_shares : {
        storage_account = k
        name            = file_share_key
        metadata        = file_share_value.metadata != null ? file_share_value.metadata : {}
        quota           = file_share_value.quota != null ? file_share_value.quota : 0
      }
    ] : []
  ]) : []

  flattened_queues = var.storage_accounts != null ? flatten([
    for k, v in var.storage_accounts :
    v.queues != null ? [
      for queue_key, queue_value in v.queues : {
        storage_account = k
        name            = queue_key
        metadata        = queue_value.metadata != null ? queue_value.metadata : {}
      }
    ] : []
  ]) : []

  flattened_tables = var.storage_accounts != null ? flatten([
    for k, v in var.storage_accounts :
    v.tables != null ? [
      for table_key, table_value in v.tables : {
        storage_account = k
        name            = table_key
      }
    ] : []
  ]) : []
}

resource "azurerm_storage_account" "this" {
  for_each = var.storage_accounts != null ? var.storage_accounts : {}

  name                            = each.value.name != null ? each.value.name : lower(substr(replace(replace("${var.project_name}${each.key}${var.environment}", "_", ""), "-", ""), 0, 24)) # Storage account name must be between 3 and 24 characters in length and can only contain numbers and lowercase letters
  resource_group_name             = each.value.resource_group_name != null ? each.value.resource_group_name : azurerm_resource_group.this.name
  location                        = each.value.location != null ? each.value.location : azurerm_resource_group.this.location
  account_kind                    = each.value.account_kind != null ? each.value.account_kind : null # StorageV2 is the default kind of storage account. Making StorageV1 into v2 will not force new resource but will upgrade existing storage to v2
  account_tier                    = each.value.account_tier != null ? each.value.account_tier : "Standard"
  account_replication_type        = each.value.account_replication_type != null ? each.value.account_replication_type : "LRS"
  access_tier                     = each.value.account_kind != null ? each.value.account_kind : null
  allow_nested_items_to_be_public = each.value.allow_nested_items_to_be_public != null ? each.value.allow_nested_items_to_be_public : null

  tags = merge(
    local.common_tags,
    each.value.tags != null ? each.value.tags : {}
  )
}

# Create containers
resource "azurerm_storage_container" "this" {
  for_each = {
    for container in local.flattened_containers :
    "${container.storage_account}-${container.name}" => container
    if local.flattened_containers != null
  }

  name                  = each.value.name
  storage_account_id    = azurerm_storage_account.this[each.value.storage_account].id
  container_access_type = each.value.access_type
  metadata              = each.value.metadata != null ? each.value.metadata : {}
}

# File shares
resource "azurerm_storage_share" "this" {
  for_each = {
    for share in local.flattened_file_shares :
    "${share.storage_account}-${share.name}" => share
    if local.flattened_file_shares != null
  }

  name               = each.value.name
  storage_account_id = azurerm_storage_account.this[each.value.storage_account].id
  metadata           = each.value.metadata != null ? each.value.metadata : {}
  quota              = each.value.quota != null ? each.value.quota : 5
  lifecycle {
    ignore_changes = [metadata]
  }
}

# Queues
resource "azurerm_storage_queue" "this" {
  for_each = {
    for queue in local.flattened_queues :
    "${queue.storage_account}-${queue.name}" => queue
    if local.flattened_queues != null
  }

  name                 = each.value.name
  storage_account_id   = azurerm_storage_account.this[each.value.storage_account].id
  metadata             = each.value.metadata != null ? each.value.metadata : {}
}

# Tables
resource "azurerm_storage_table" "this" {
  for_each = {
    for table in local.flattened_tables :
    "${table.storage_account}-${table.name}" => table
    if local.flattened_tables != null
  }

  name                 = each.value.name
  storage_account_name = azurerm_storage_account.this[each.value.storage_account].name
}

resource "azurerm_private_endpoint" "storage" {
  for_each = local.storage_accounts_with_private_endpoint

  name                          = "${replace(lower(var.project_name), "-", "")}${lower(var.environment)}-storage-pe"
  location                      = var.location
  resource_group_name           = azurerm_storage_account.this[each.key].resource_group_name
  subnet_id                     = each.value.private_endpoint.subnet_id
  custom_network_interface_name = "${replace(lower(var.project_name), "-", "")}${lower(var.environment)}-storage-pe-nic"

  private_service_connection {
    name                           = "${replace(lower(var.project_name), "-", "")}${lower(var.environment)}-storage-pe"
    private_connection_resource_id = azurerm_storage_account.this[each.key].id
    is_manual_connection           = false
    subresource_names              = [each.value.private_endpoint.endpoint_type]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = each.value.private_endpoint.private_dns_zone_ids
  }

  tags = merge(
    local.common_tags
  )
}
