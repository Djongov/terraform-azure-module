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

variable "app_service_certificates" {
  type = map(object({
    dns_name          = string           # Must be in "CN=example.com" format
    product_type      = string           # Possible values are Standard or WildCard
    auto_renew        = optional(bool)   # Default to true
    key_size          = optional(number) # Default to 2048
    validity_in_years = optional(number) # Default to 1, 1 or 3
  }))
  default = {}
}

variable "app_service_plans" {
  type = map(object({
    sku                      = string
    os_type                  = string
    worker_count             = optional(number)
    key                      = optional(string)
    name                     = optional(string)
    location                 = optional(string)
    tags                     = optional(map(string))
    zone_balancing_enabled   = optional(bool)
    per_site_scaling_enabled = optional(bool)
  }))
  default = {}
}

variable "webapp_ssl_certificates" {
  type = object({
    locations = map(map(object({
      # If we want to pull a "certificate" type of secret from the key vault use this
      certificate_name = optional(string)
      # If we want to pull a "secret" type of secret from the key vault use this. This is recommended as it stays in sync with the actual App Service Certificate
      secret_name = optional(string)
      # The key vault ID
      key_vault_id = string
      tags         = optional(map(string))
    })))
  })
  default = {
    locations = {}
  }
}

variable "web_apps" {
  description = "This map is used to deploy Azure App Service web apps"
  type = map(
    object(
      {
        # ================ Custom params ================ #
        # The key is optional and is used if we want to override the key naming convention
        key = optional(string)
        # The app service plan to attach to
        app_service_plan = string
        # Mount app settings from key vault. The key of the map is just a name to identify the configuration, and has no functional purpose.
        app_settings_from_key_vault = optional(map(object({
          # Each key will be a key vault reference, and a Key Vault Secrets User role will be created for the web app's managed identity on that key vault, and the secrets will be pulled from there. The value of the map is an object with the following properties:
          # One of the two needs to be provided
          key_vault_id  = optional(string) # this is if the key vault is in remote project
          key_vault_key = optional(string) # this is if the key vault is local and we want to reference it by the key in the key vaults variable
          app_settings  = map(string)      # this will be a map of app settings, keys are what the env var name should be, the values are the secret names in the key vault
        })))
        # The custom domains map of objects. Needs to point to the name of the certificate in the webapp_ssl_certificates map
        custom_domains = optional(map(object({
          key_vault_certificate           = optional(string)
          app_service_managed_certificate = optional(bool)
        })))
        # =============== Standard params ================ #
        # To completely override the name of the app service, used in imports or special cases
        name = optional(string)
        # The app settings
        app_settings = map(string)
        autoheal = optional(object({
          action = object({
            action_type                    = string # "Recycle", "Log", or "CustomAction"
            minimum_process_execution_time = optional(string)
          })
          trigger = object({
            # For now we only do status_code
            count             = number
            interval          = string
            status_code_range = string # e.g. "400-499" or "500-599"
            sub_status        = optional(number)
            win32_status_code = optional(number) # e.g. 0, 1, 2, etc.
            }
        ) }))
        alert_rules = optional(object({
          resource_health = optional(object({
            enabled         = bool
            action_group_id = string
          }))
          container_failures = optional(object({
            enabled         = bool
            action_group_id = string
          }))
        }))
        # enable/disable switch
        enabled = optional(bool)
        # https only switch
        https_only = optional(bool)
        # client affinity switch
        client_affinity_enabled = optional(bool)
        # client certificate enabled switch
        ftp_publish_basic_authentication_enabled = optional(bool)
        # vnet integraiton turns on by providing the vnet and subnet in the format #RG/VNET/Subnet
        vnet_integration              = optional(string)
        public_network_access_enabled = optional(bool)
        # Whether to attach to the application insights
        application_insights = optional(string)
        # Site config
        site_config = object({
          always_on                               = optional(bool)
          worker_count                            = optional(number)
          ftps_state                              = optional(string)
          http2_enabled                           = optional(bool)
          health_check_path                       = optional(string)
          health_check_eviction_time_in_min       = optional(number)
          use_32_bit_worker_process               = optional(bool)
          ip_restriction_default_action           = optional(string)
          scm_ip_restriction_default_action       = optional(string)
          vnet_route_all_enabled                  = optional(bool)
          websockets_enabled                      = optional(bool)
          app_command_line                        = optional(string)
          container_registry_use_managed_identity = optional(bool)
          //scm_type                                = optional(string)
          use_32_bit_worker   = optional(bool)
          local_mysql_enabled = optional(bool)
          cors = optional(object({
            allowed_origins     = list(string)
            support_credentials = optional(bool)
          }))
          virtual_applications = optional(list(object({
            physical_path = string
            preload       = bool
            virtual_path  = string
          })))
        })
        # Identity
        identity = optional(object({
          type         = string                 # "SystemAssigned", "UserAssigned", or "SystemAssigned, UserAssigned"
          identity_ids = optional(list(string)) # Required if UserAssigned is included
        }))
        # Application stack
        application_stack = object({
          # If deploying code
          php_version         = optional(string)
          java_version        = optional(string)
          node_version        = optional(string)
          python_version      = optional(string)
          dotnet_version      = optional(string)
          ruby_version        = optional(string)
          dotnet_core_version = optional(string)
          # If mounting an image from a container registry
          docker_image_name     = optional(string)
          docker_registry_url   = optional(string)
          acr_id                = optional(string) # Full ARM resource ID of the ACR. Used for webhook, acrpull role assignment, and the hidden-link tag
          acr_location          = optional(string) # Required when the ACR is in a different subscription; skips the data source lookup and uses this location for the webhook
          continuous_deployment = optional(bool)
        })
        source_control = optional(object({
          repo_url               = string
          branch                 = optional(string)
          use_manual_integration = optional(bool)
          type                   = optional(string) # Possible values are "GitHub", "Bitbucket", "ExternalGit", "LocalGit", "OneDrive", "Dropbox", "AzureDevOps"
          token = optional(object({
            type                     = string # Possible values are "GitHub", "AzureDevOps", "Bitbucket", "GitLab"
            key_vault_name           = string
            key_vault_resource_group = string
            secret_name              = string
          }))
          github_action_configuration = optional(object({
            generate_workflow_file = optional(bool, false)
            container_configuration = optional(object({
              image_name   = string
              registry_url = string
            }))
          }))
        }))
        # App Service Logs
        logs = optional(object(
          {
            detailed_error_messages = optional(bool)
            failed_request_tracing  = optional(bool)
            http_logs = optional(object({
              azure_blob_storage = optional(object({
                retention_in_days = optional(number) # 0 means no retention
                sas_url           = string
              }))
              file_system = optional(object({
                retention_in_days = number
                retention_in_mb   = number
              }))
            }))
            application_logs = optional(object(
              {
                azure_blob_storage = optional(object(
                  {
                    level             = string # Possible values include Error, Warning, Information, Verbose and Off
                    retention_in_days = number
                    sas_url           = string
                  }
                ))
                file_system_level = string # Possible values include: Off, Verbose, Information, Warning, and Error.
              }
            ))
          }
        ))
        # Diagnostic settings
        diagnostic_settings = optional(map(object({
          name                           = optional(string)
          log_analytics_workspace_id     = optional(string)
          storage_account_id             = optional(string)
          eventhub_namespace             = optional(string)
          eventhub_authorization_rule_id = optional(string)
          log_categories = object({
            AppServiceHTTPLogs       = optional(bool)
            AppServiceConsoleLogs    = optional(bool)
            AppServiceAppLogs        = optional(bool) # Only for ASP.NET (Windows) and Java SE & Tomcat (Linux)
            AppServiceAuditLogs      = optional(bool)
            AppServicePlatformLogs   = optional(bool)
            AppServiceIPSecAuditLogs = optional(bool)
            AllMetrics               = optional(bool)
          })
        })))
        # Creates a priority 100 rule to allow traffic from the Front Door id only
        allow_front_door_access_restriction_front_door_id = optional(string)
        # A list of custom defined IP restrictions
        custom_ip_restrictions = optional(list(object({
          name                      = string
          action                    = string
          priority                  = number
          ip_address                = optional(string)
          service_tag               = optional(string)
          description               = optional(string)
          virtual_network_subnet_id = optional(string)
          headers = optional(list(object({
            x_azure_fdid      = list(string)
            x_fd_health_probe = list(string)
            x_forwarded_for   = list(string)
            x_forwarded_host  = list(string)
          })))
        })))
        tags = optional(map(string))
      }
    )
  )
  default = {}
}