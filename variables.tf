variable "project_name" {
  description = "Important for naming resources. It is used in the naming convention for all resources. It should be short and descriptive."
  type        = string
}

variable "location" {
  description = "General resource location"
  type        = string
}

variable "environment" {
  description = "Environment for the application. I.e. dev, staging, prod"
  type        = string
}

variable "subscription_id" {
  description = "Subscription id where the resources will be deployed"
  type        = string
}

variable "common_tags" {
  description = "Common tags to be applied to all resources. It is a map of key-value pairs."
  type        = map(string)
  default     = {}
}

variable "storage_accounts" {
  description = "Create storage accounts"
  type = map(
    object(
      {
        name                            = optional(string) # Overrides default naming
        resource_group_name             = optional(string) # Deploys in different than the module's resource group
        location                        = optional(string) # Overrides default location from var.location
        account_tier                    = optional(string) # Standard and Premium. For BlockBlobStorage and FileStorage accounts only Premium is valid
        account_kind                    = optional(string) # BlobStorage, BlockBlobStorage, FileStorage, Storage and StorageV2. Defaults to StorageV2
        account_replication_type        = optional(string) # Valid options are LRS, GRS, RAGRS, ZRS, GZRS and RAGZRS. Defaults to LRS
        access_tier                     = optional(string) # Defines the access tier for BlobStorage, FileStorage and StorageV2 accounts. Valid options are Hot, Cool, Cold and Premium. Defaults to Hot.
        allow_nested_items_to_be_public = optional(bool)
        containers = optional(map(object({
          access_type = string
          metadata    = optional(map(string))
        })))
        file_shares = optional(map(object({
          metadata = optional(map(string))
          quota    = optional(number)
        })))
        tables = optional(map(object({
          metadata = optional(map(string))
        })))
        queues = optional(map(object({
          metadata = optional(map(string))
        })))
        private_endpoint = optional(object({
          endpoint_type        = string
          subnet_id            = string
          private_dns_zone_ids = list(string)
        }))
        tags = optional(map(string))
      }
  ))
  default = {}
}

variable "key_vaults" {
  description = "Create rbac_authorization_enabled Key Vaults"
  type = map(
    object(
      {
        name                = optional(string)             # Overrides default naming
        resource_group_name = optional(string)             # Deploys in different than the module's resource group
        location            = optional(string)             # Overrides default location from var.location
        sku_name            = optional(string, "standard") # "standard" or "premium"

        public_network_access_enabled = optional(bool, true)     # # Defaults to true
        network_bypass                = optional(string, "None") # "AzureServices" or "None"
        network_default_action        = optional(string, "Deny") # "Allow" or "Deny"
        ip_rules                      = optional(list(string))

        subnet_key = optional(string) # The subnet key from var.vnet.subnets to link the key vault to
        subnet_id  = optional(string) # Alternative to subnet_key, provide the actual subnet ID

        soft_delete_retention_days = optional(number, 7)
        provider_access            = optional(list(string), []) # e.g. ["Microsoft.Azure.CertificateRegistration", "Microsoft Azure WebSites", "Microsoft.AzureFrontDoor-Cdn"]
        # Ability to create random secrets in the key vault
        random_secrets = optional(map(object({
          length           = number
          lower            = optional(bool, true)
          upper            = optional(bool, true)
          numeric          = optional(bool, true)
          special          = optional(bool, true)
          min_lower        = optional(number, null)
          min_upper        = optional(number, null)
          min_numeric      = optional(number, null)
          min_special      = optional(number, null)
          override_special = optional(string)
        })))
        iam = optional(object({
          users              = optional(map(list(string))) # Map of usernames to lists of roles
          groups             = optional(map(list(string))) # Map of group names to lists of roles
          service_principals = optional(map(list(string))) # Map of service principal object IDs to lists of roles
        }))
        tags = optional(map(string))
      }
  ))
  default = {}
}

variable "static_web_apps" {
  description = "Specifies the static web apps to be deployed."
  type = map(
    object(
      {
        location                           = optional(string)
        resource_group_name                = optional(string)
        configuration_file_changes_enabled = optional(bool)
        preview_environments_enabled       = optional(bool)
        public_network_access_enabled      = optional(bool)
        sku                                = string
        custom_domains = optional(list(object({
          domain_name     = string # actual domain
          validation_type = string # cname-delegation or dns-txt-token
        })))
        identity = optional(object({
          type                      = string
          user_assigned_identity_id = optional(string)
        }))
        tags = optional(map(string))
      }
    )
  )
  default = {}
}

variable "postgresql_flexible_servers" {
  description = "Map of PostgreSQL flexible servers to create"
  type = map(
    object({
      # Required
      version       = string           # 11,12, 13, 14, 15, 16, 17, and 18
      sku_name      = string           # B_Standard_B1ms lowest SKU
      storage_mb    = number           # min 32768, or one of [32768 65536 131072 262144 524288 1048576 2097152 4193280 4194304 8388608 16777216 33553408]
      key_vault_id  = optional(string) # this is a remote key vault to store the administrator password in. Is null, will have to use a local project key vault
      key_vault_key = optional(string) # this is the key of a local key vault where the administrator password will be stored
      # Optional server configuration
      name                          = optional(string)
      subnet_key                    = optional(string) # This will trigger a private endpoint connection. What needs to be passed is the string of the subnet key from vnet var
      subnet_id                     = optional(string) # Alternative to subnet_key, provide the actual subnet ID
      zone                          = optional(string) # Default is "1"
      storage_tier                  = optional(string) # Default is null, which means the default storage tier will be used
      public_network_access_enabled = optional(bool)   # Default is true

      # High availability configuration
      high_availability = optional(object({
        mode                      = string           # Possible values are "Disabled", "ZoneRedundant", and "SameZone"
        standby_availability_zone = optional(string) # Required if mode is "SameZone"
      }))

      # Backup configuration
      geo_redundant_backup_enabled = optional(bool)
      auto_grow_enabled            = optional(bool)
      backup_retention_days        = optional(number) # Default is 7

      # Authentication and security
      administrator_login               = optional(string, "pgadmin") # Default is "pgadmin"
      administrator_password_wo         = optional(string)            # Password for the administrator, used only when create_mode is not "Default"
      administrator_password_wo_version = optional(number)            # Version of the administrator password, used only when create_mode is not "Default"
      create_mode                       = optional(string)            # Default is "Default", other values are "Replica", "GeoRestore", and "PointInTimeRestore"
      active_directory_auth_enabled     = optional(bool)              # Default is false
      password_auth_enabled             = optional(bool)              # Default is true

      # Identity configuration
      identity = optional(object({
        type         = string                 # "SystemAssigned" or "UserAssigned"
        identity_ids = optional(list(string)) # Required if type is "UserAssigned"
      }))

      diagnostic_settings = optional(map(object({
        name                           = optional(string)
        log_analytics_workspace_id     = optional(string)
        storage_account_id             = optional(string)
        eventhub_namespace             = optional(string)
        eventhub_authorization_rule_id = optional(string)
        log_categories = object({
          PostgreSQLLogs                    = optional(bool)
          PostgreSQLFlexDatabaseXacts       = optional(bool)
          PostgreSQLFlexQueryStoreRuntime   = optional(bool)
          PostgreSQLFlexQueryStoreWaitStats = optional(bool)
          PostgreSQLFlexSessions            = optional(bool)
          PostgreSQLFlexTableStats          = optional(bool)
          AllMetrics                        = optional(bool)
        })
      })))

      # Firewall rules
      allow_firewall_webapp = optional(string) # This is the key of the web app that will be allowed to access the PostgreSQL server
      firewall_rules = optional(map(object({
        name             = optional(string)
        start_ip_address = string
        end_ip_address   = string
      })))

      # Databases to create on this server
      databases = optional(map(object({
        name      = optional(string)
        charset   = optional(string, "UTF8")       # Default is "UTF8"
        collation = optional(string, "en_US.utf8") # Default is "en_US.utf8"
      })), {})

      # Tags
      tags = optional(map(string))
    })
  )
  default = {}
}
