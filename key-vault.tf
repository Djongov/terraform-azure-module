locals {
  key_vault_cert_reg_vaults = {
    for kv_key, kv in var.key_vaults :
    kv_key => kv
    if contains(kv.provider_access, "Microsoft.Azure.CertificateRegistration")
  }

  key_vault_app_service_vaults = {
    for kv_key, kv in var.key_vaults :
    kv_key => kv
    if contains(kv.provider_access, "Microsoft Azure WebSites")
  }

  key_vault_front_door_vaults = {
    for kv_key, kv in var.key_vaults :
    kv_key => kv
    if contains(kv.provider_access, "Microsoft.AzureFrontDoor-Cdn")
  }

  kv_secrets_flat = {
    for item in flatten([
      for kv_key, kv in var.key_vaults : [
        for secret_key, secret in coalesce(kv.random_secrets, {}) : {
          key        = "${kv_key}__${secret_key}"
          kv_key     = kv_key
          secret_key = secret_key
          config     = secret
        }
      ]
    ]) : item.key => item
  }
}

resource "azurerm_key_vault" "this" {
  for_each = var.key_vaults

  name                          = each.value.name != null ? each.value.name : substr(lower(replace("${var.project_name}-${each.key}-kv-${var.environment}-${local.location_abbreviation}", "_", "-")), 0, 24)
  resource_group_name           = coalesce(each.value.resource_group_name, azurerm_resource_group.this.name)
  location                      = coalesce(each.value.location, azurerm_resource_group.this.location)
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = each.value.sku_name
  public_network_access_enabled = each.value.public_network_access_enabled != null ? each.value.public_network_access_enabled : null
  rbac_authorization_enabled    = true

  soft_delete_retention_days = each.value.soft_delete_retention_days

  purge_protection_enabled = false
  #enabled_for_disk_encryption = true

  network_acls {
    bypass         = each.value.network_bypass
    default_action = each.value.network_default_action
    ip_rules       = coalesce(each.value.ip_rules, [])
    # virtual_network_subnet_ids = each.value.subnet_id != null ? [each.value.subnet_id] : (
    #   each.value.subnet_key != null ? [
    #     azurerm_subnet.vnet_subnets[each.value.subnet_key].id
    #   ] : []
    # )
  }

  tags = merge(
    local.common_tags,
    each.value.tags != null ? each.value.tags : {}
  )
}

resource "random_password" "kv_secrets" {
  for_each = local.kv_secrets_flat

  length           = each.value.config.length
  lower            = each.value.config.lower
  upper            = each.value.config.upper
  numeric          = each.value.config.numeric
  special          = each.value.config.special
  min_lower        = each.value.config.min_lower
  min_upper        = each.value.config.min_upper
  min_numeric      = each.value.config.min_numeric
  min_special      = each.value.config.min_special
  override_special = try(each.value.config.override_special, null)
}

resource "azurerm_key_vault_secret" "random" {
  for_each = local.kv_secrets_flat

  name         = each.value.secret_key
  value        = random_password.kv_secrets[each.key].result
  key_vault_id = azurerm_key_vault.this[each.value.kv_key].id
}

# Microsoft.Azure.CertificateRegistration in reality, the same to trigger
resource "azurerm_role_assignment" "cert_registration" {
  for_each = local.key_vault_cert_reg_vaults

  scope                = azurerm_key_vault.this[each.key].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = "00525208-fd21-4ef9-ab6d-bed669bf9bd3"
}

# Microsoft Azure WebSites in reality, the same to trigger
resource "azurerm_role_assignment" "app_service" {
  for_each = local.key_vault_app_service_vaults

  scope                = azurerm_key_vault.this[each.key].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = "dcc52a75-45aa-4567-a218-5d51f93f2409"
}

resource "azurerm_role_assignment" "front_door" {
  for_each = local.key_vault_front_door_vaults

  scope                = azurerm_key_vault.this[each.key].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = "6d82884c-070a-4d69-abb1-f4941fbe9efa"
}

# Fetch Azure AD users for Key Vault IAM
data "azuread_user" "key_vault_users" {
  for_each = toset(flatten([
    for kv_key, kv in var.key_vaults :
    keys(coalesce(try(kv.iam.users, null), {}))
  ]))

  user_principal_name = each.value
}

data "azuread_group" "key_vault_groups" {
  for_each = toset(flatten([
    for kv_key, kv in var.key_vaults :
    keys(coalesce(try(kv.iam.groups, null), {}))
  ]))

  display_name = each.value
}

data "azuread_service_principal" "key_vault_spns" {
  for_each = toset(flatten([
    for kv_key, kv in var.key_vaults :
    keys(coalesce(try(kv.iam.service_principals, null), {}))
  ]))

  display_name = each.value
}

# Now assign roles to users, groups, and service principals
resource "azurerm_role_assignment" "key_vault_user_iam" {
  for_each = merge([
    for kv_key, kv in var.key_vaults : {
      for item in flatten([
        for username, roles in coalesce(try(kv.iam.users, null), {}) : [
          for role in toset(roles) : {
            key      = "${kv_key}__${username}__${role}"
            username = username
            role     = role
            kv_key   = kv_key
          }
        ]
      ]) : item.key => item
    }
  ]...)

  role_definition_name = each.value.role
  principal_id         = data.azuread_user.key_vault_users[each.value.username].object_id
  scope                = azurerm_key_vault.this[each.value.kv_key].id
}

resource "azurerm_role_assignment" "key_vault_group_iam" {
  for_each = merge([
    for kv_key, kv in var.key_vaults : {
      for item in flatten([
        for groupname, roles in coalesce(try(kv.iam.groups, null), {}) : [
          for role in toset(roles) : {
            key       = "${kv_key}__${groupname}__${role}"
            groupname = groupname
            role      = role
            kv_key    = kv_key
          }
        ]
      ]) : item.key => item
    }
  ]...)

  role_definition_name = each.value.role
  principal_id         = data.azuread_group.key_vault_groups[each.value.groupname].object_id
  scope                = azurerm_key_vault.this[each.value.kv_key].id
}

resource "azurerm_role_assignment" "key_vault_spn_iam" {
  for_each = merge([
    for kv_key, kv in var.key_vaults : {
      for item in flatten([
        for spn, roles in coalesce(try(kv.iam.service_principals, null), {}) : [
          for role in toset(roles) : {
            key    = "${kv_key}__${spn}__${role}"
            spn    = spn
            role   = role
            kv_key = kv_key
          }
        ]
      ]) : item.key => item
    }
  ]...)

  role_definition_name = each.value.role
  principal_id         = data.azuread_service_principal.key_vault_spns[each.value.spn].object_id
  scope                = azurerm_key_vault.this[each.value.kv_key].id
}
