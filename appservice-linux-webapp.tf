locals {
  # This is used to get the location abbreviation for app service plans, which may have different locations than the resource group
  location_abbreviation_app_service_plan = var.app_service_plans != null ? {
    for k, v in var.app_service_plans : k => lookup(local.location_abbreviations, coalesce(v.location, var.location), "")
  } : {}

  app_service_webapp_diagnostic_settings = merge([
    for web_app_key, web_app_value in var.web_apps != null ? var.web_apps : {} : {
      for diag_key, diag in web_app_value.diagnostic_settings != null ? web_app_value.diagnostic_settings : {} :
      "${web_app_key}-${diag_key}" => {
        web_app                        = web_app_key
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

  linux_web_apps_with_domains = var.app_service_plans != null ? flatten([
    for k, v in(var.web_apps != null ? var.web_apps : {}) : [
      for domain, settings in(v["custom_domains"] != null ? v["custom_domains"] : {}) : {
        app_key               = k
        app_service_plan      = v.app_service_plan
        domain                = domain
        key_vault_certificate = lookup(settings, "key_vault_certificate", null)
      }
    ] if v["custom_domains"] != null && lookup(var.app_service_plans, v.app_service_plan, null) != null && var.app_service_plans[v.app_service_plan].os_type == "Linux"
  ]) : []

  # Filter for var.webapp_ssl_certificates and make a map of certificates that need to be pulled from key vault
  key_vault_certificates = var.webapp_ssl_certificates != null ? tomap({
    for kv in flatten([
      for location, certs in var.webapp_ssl_certificates.locations : [
        for cert_name, cert_details in certs : {
          key = "${location}.${cert_name}"
          value = merge(
            cert_details,
            {
              location = location,
              key      = cert_name,
              provider = lookup(cert_details, "provider", null)
              name     = lookup(cert_details, "name", null)
            }
          )
        }
      ]
    ]) : kv.key => kv.value
  }) : {}

  # Secondary lookup by cert_name only (for use in custom_domains where only the cert name is given)
  key_vault_certificates_by_name = {
    for k, v in local.key_vault_certificates : v.key => v
  }

  # # Filter for Linux web apps with key vault certificates with certificate_name not null
  linux_web_apps_with_key_vault_certificates = var.web_apps != null && var.app_service_plans != null ? flatten([
    for app_key, app_value in var.web_apps : [
      for domain, domain_settings in(app_value.custom_domains != null ? app_value.custom_domains : {}) : {
        app_key          = app_key
        domain           = domain
        app_service_plan = app_value.app_service_plan
        ssl_certificate  = domain_settings
        provider = lookup(
          try(local.key_vault_certificates_by_name[domain_settings.key_vault_certificate], {}),
          "provider",
          null
        )
        secret_name = lookup(
          try(local.key_vault_certificates_by_name[domain_settings.key_vault_certificate], {}),
          "secret_name",
          null
        )
        certificate_name = lookup(
          try(local.key_vault_certificates_by_name[domain_settings.key_vault_certificate], {}),
          "certificate_name",
          null
        )
        certificate_full_key = try(
          local.key_vault_certificates_by_name[domain_settings.key_vault_certificate] != null
          ? "${local.key_vault_certificates_by_name[domain_settings.key_vault_certificate].location}.${domain_settings.key_vault_certificate}"
          : null,
          null
        )
      }
      if(
        domain_settings.app_service_managed_certificate == null &&
        domain_settings.key_vault_certificate != null &&
        lookup(var.app_service_plans, app_value.app_service_plan, null) != null &&
        var.app_service_plans[app_value.app_service_plan].os_type == "Linux"
      )
    ]
  ]) : []

  app_settings_from_kv_resolved = var.web_apps != null ? {
    for app_name, app in var.web_apps :
    app_name => merge([
      for kv_ref_key, kv_ref in coalesce(app.app_settings_from_key_vault, {}) : {
        for envvar, secret_name in kv_ref.app_settings :
        envvar => "@Microsoft.KeyVault(VaultName=${kv_ref.key_vault_key != null ? azurerm_key_vault.this[kv_ref.key_vault_key].name : split("/", kv_ref.key_vault_id)[8]};SecretName=${secret_name})"
      }
    ]...)
  } : {}

  webapp_kv_app_settings_role_assignments = {
    for item in flatten([
      for app_name, app in coalesce(var.web_apps, {}) : [
        for kv_ref_key, kv_ref in coalesce(app.app_settings_from_key_vault, {}) : {
          key           = "${app_name}-${kv_ref_key}"
          app_name      = app_name
          key_vault_key = kv_ref.key_vault_key
          key_vault_id  = kv_ref.key_vault_id
        }
      ]
    ]) : item.key => item
  }

  # Derive GitHub Actions code_configuration from application_stack
  webapp_github_code_config = {
    for app_name, app in coalesce(var.web_apps, {}) :
    app_name => (
      lookup(app.application_stack, "node_version", null) != null ? {
        runtime_stack   = "node"
        runtime_version = app.application_stack.node_version
        } : lookup(app.application_stack, "python_version", null) != null ? {
        runtime_stack   = "python"
        runtime_version = app.application_stack.python_version
        } : lookup(app.application_stack, "dotnet_version", null) != null ? {
        runtime_stack   = "dotnetcore"
        runtime_version = app.application_stack.dotnet_version
        } : lookup(app.application_stack, "dotnet_core_version", null) != null ? {
        runtime_stack   = "dotnetcore"
        runtime_version = app.application_stack.dotnet_core_version
        } : lookup(app.application_stack, "java_version", null) != null ? {
        runtime_stack   = "spring"
        runtime_version = app.application_stack.java_version
      } : null
    )
  }
}

# ===================== Linux Web App =====================
resource "azurerm_linux_web_app" "this" {
  for_each = var.web_apps != null && var.app_service_plans != null ? {
    for k, v in var.web_apps : k => v if var.app_service_plans[v.app_service_plan].os_type == "Linux"
  } : {}

  # The name can be overriden by the name variable but for consistency, I discourage it
  name = each.value.name != null ? each.value.name : lower("${var.project_name}-${each.value.key != null ? each.value.key : each.key}-${var.environment}-${local.location_abbreviation_app_service_plan[each.value.app_service_plan]}")
  # Imoportant that we set the location to that of the app service plan and not the resource group, as the app service plan may be in a different location than the resource group
  location            = azurerm_service_plan.this[each.value.app_service_plan].location
  resource_group_name = azurerm_resource_group.this.name
  # If the app_service_plan starts with /subscriptions, we must be passing the ID directly, which allows for remote app service plans to be used instead of the local ones
  service_plan_id = azurerm_service_plan.this[each.value.app_service_plan].id

  https_only                               = each.value.https_only != null ? each.value.https_only : true
  enabled                                  = each.value.enabled != null ? each.value.enabled : true
  client_affinity_enabled                  = each.value.client_affinity_enabled != null ? each.value.client_affinity_enabled : false
  ftp_publish_basic_authentication_enabled = each.value.ftp_publish_basic_authentication_enabled != null ? each.value.ftp_publish_basic_authentication_enabled : false

  #virtual_network_subnet_id = each.value.vnet_integration != null ? data.azurerm_subnet.webapps_vnet_integration[each.key].id : null

  app_settings = merge(
    each.value.app_settings,
    # each.value.application_insights != null ? {
    #   "APPINSIGHTS_INSTRUMENTATIONKEY" = data.azurerm_application_insights.default[each.value.application_insights].instrumentation_key
    # } : {},
    lookup(each.value.application_stack, "continuous_deployment", null) == true ? {
      "DOCKER_ENABLE_CI" = "true"
    } : {},
    local.app_settings_from_kv_resolved[each.key]
  )

  public_network_access_enabled = each.value.public_network_access_enabled != null ? each.value.public_network_access_enabled : true

  site_config {
    always_on                               = each.value.site_config["always_on"] != null ? each.value.site_config["always_on"] : true
    worker_count                            = each.value.site_config["worker_count"] != null ? each.value.site_config["worker_count"] : null
    ftps_state                              = each.value.site_config["ftps_state"] != null ? each.value.site_config["ftps_state"] : "Disabled"
    local_mysql_enabled                     = each.value.site_config["local_mysql_enabled"] != null ? each.value.site_config["local_mysql_enabled"] : false
    http2_enabled                           = each.value.site_config["http2_enabled"] != null ? each.value.site_config["http2_enabled"] : true
    health_check_path                       = each.value.site_config["health_check_path"] != null ? each.value.site_config["health_check_path"] : null
    health_check_eviction_time_in_min       = each.value.site_config["health_check_eviction_time_in_min"] != null ? each.value.site_config["health_check_eviction_time_in_min"] : null
    use_32_bit_worker                       = each.value.site_config["use_32_bit_worker"] != null ? each.value.site_config["use_32_bit_worker"] : false
    container_registry_use_managed_identity = each.value.site_config["container_registry_use_managed_identity"] != null ? each.value.site_config["container_registry_use_managed_identity"] : false
    app_command_line                        = each.value.site_config["app_command_line"] != null ? each.value.site_config["app_command_line"] : null
    websockets_enabled                      = each.value.site_config["websockets_enabled"] != null ? each.value.site_config["websockets_enabled"] : false
    ip_restriction_default_action           = each.value.site_config["ip_restriction_default_action"] != null ? each.value.site_config["ip_restriction_default_action"] : lookup(each.value, "allow_front_door_access_restriction_front_door_id", null) != null ? "Deny" : "Allow"
    scm_ip_restriction_default_action       = each.value.site_config["scm_ip_restriction_default_action"] != null ? each.value.site_config["scm_ip_restriction_default_action"] : "Allow"
    vnet_route_all_enabled                  = each.value.site_config["vnet_route_all_enabled"] != null ? each.value.site_config["vnet_route_all_enabled"] : null
    //scm_type                                = each.value.site_config["scm_type"] != null ? each.value.site_config["scm_type"] : "None"

    application_stack {
      php_version         = lookup(each.value.application_stack, "php_version", null)
      java_version        = lookup(each.value.application_stack, "java_version", null)
      node_version        = lookup(each.value.application_stack, "node_version", null)
      python_version      = lookup(each.value.application_stack, "python_version", null)
      dotnet_version      = lookup(each.value.application_stack, "dotnet_version", null)
      ruby_version        = lookup(each.value.application_stack, "ruby_version", null)
      docker_image_name   = lookup(each.value.application_stack, "docker_image_name", null)
      docker_registry_url = lookup(each.value.application_stack, "docker_registry_url", null)
    }
    # Now for the default ones
    # Front Door one
    dynamic "ip_restriction" {
      for_each = each.value.allow_front_door_access_restriction_front_door_id != null ? [1] : []

      content {
        action      = "Allow"
        name        = "Allow Front Door"
        priority    = 100
        service_tag = "AzureFrontDoor.Backend"
        headers = [
          {
            x_azure_fdid      = ["${each.value.allow_front_door_access_restriction_front_door_id}"]
            x_fd_health_probe = []
            x_forwarded_for   = []
            x_forwarded_host  = []
          }
        ]
      }
    }

    # To allow internal pings always on and healthchecks to still work when front door restriction is in place
    # dynamic "ip_restriction" {
    #   for_each = each.value.allow_front_door_access_restriction_front_door_id != null ? [1] : []

    #   content {
    #     name        = "Allow AppServiceManagement"
    #     priority    = 110
    #     action      = "Allow"
    #     service_tag = "AppServiceManagement"
    #   }
    # }

    # Now is there are any custom restrictions, create them
    dynamic "ip_restriction" {
      for_each = each.value.custom_ip_restrictions != null ? each.value.custom_ip_restrictions : []

      content {
        name                      = ip_restriction.value["name"]
        action                    = ip_restriction.value["action"]
        priority                  = ip_restriction.value["priority"]
        ip_address                = lookup(ip_restriction.value, "ip_address", null)
        service_tag               = lookup(ip_restriction.value, "service_tag", null)
        headers                   = lookup(ip_restriction.value, "headers", [])
        virtual_network_subnet_id = lookup(ip_restriction.value, "virtual_network_subnet_id", null)
      }
    }

    # CORS settings
    dynamic "cors" {
      # If the identity type is not null, then create the identity block
      for_each = each.value.site_config["cors"] != null ? [1] : []

      content {
        allowed_origins     = each.value.site_config["cors"]["allowed_origins"]
        support_credentials = can(each.value.site_config["cors"]["support_credentials"] != null) ? each.value.site_config["cors"]["support_credentials"] : false
      }
    }

    dynamic "auto_heal_setting" {
      for_each = each.value.autoheal != null ? [1] : []

      content {
        action {
          action_type                    = each.value.autoheal.action.action_type
          minimum_process_execution_time = each.value.autoheal.action.minimum_process_execution_time
        }
        trigger {
          status_code {
            count             = each.value.autoheal.trigger.count
            interval          = each.value.autoheal.trigger.interval
            status_code_range = each.value.autoheal.trigger.status_code_range
            sub_status        = each.value.autoheal.trigger.sub_status != null ? each.value.autoheal.trigger.sub_status : 0
            win32_status_code = each.value.autoheal.trigger.win32_status_code != null ? each.value.autoheal.trigger.win32_status_code : 0
          }
        }
      }
    }
  }

  dynamic "identity" {
    for_each = (each.value.identity != null || (each.value.source_control != null && each.value.source_control.type == "GitHub")) ? [1] : []

    content {
      type = each.value.identity != null && each.value.identity.type == "SystemAssigned, UserAssigned" ? "SystemAssigned, UserAssigned" : (
        each.value.identity != null ? each.value.identity.type : "UserAssigned"
      )

      identity_ids = concat(
        each.value.identity != null && can(regex("UserAssigned", each.value.identity.type)) ? coalesce(each.value.identity.identity_ids, []) : [],
        each.value.source_control != null && each.value.source_control.type == "GitHub" ? [azurerm_user_assigned_identity.github_integration[each.key].id] : []
      )
    }
  }


  dynamic "logs" {
    for_each = each.value.logs != null ? [1] : []

    content {
      detailed_error_messages = try(each.value.logs.detailed_error_messages, null)
      failed_request_tracing  = try(each.value.logs.failed_request_tracing, null)

      dynamic "http_logs" {
        for_each = each.value.logs.http_logs != null ? [1] : []

        content {
          dynamic "azure_blob_storage" {
            for_each = each.value.logs.http_logs.azure_blob_storage != null ? [1] : []

            content {
              retention_in_days = try(each.value.logs.http_logs.azure_blob_storage.retention_in_days, null)
              sas_url           = sensitive(each.value.logs.http_logs.azure_blob_storage.sas_url)
            }
          }

          dynamic "file_system" {
            for_each = each.value.logs.http_logs.file_system != null ? [1] : []

            content {
              retention_in_days = each.value.logs.http_logs.file_system.retention_in_days
              retention_in_mb   = each.value.logs.http_logs.file_system.retention_in_mb
            }
          }
        }
      }

      dynamic "application_logs" {
        for_each = each.value.logs.application_logs != null ? [1] : []

        content {
          dynamic "azure_blob_storage" {
            for_each = each.value.logs.application_logs.azure_blob_storage != null ? [1] : []

            content {
              level             = each.value.logs.application_logs.azure_blob_storage.level
              retention_in_days = each.value.logs.application_logs.azure_blob_storage.retention_in_days
              sas_url           = sensitive(each.value.logs.application_logs.azure_blob_storage.sas_url)
            }
          }

          file_system_level = each.value.logs.application_logs.file_system_level
        }
      }
    }
  }

  tags = merge(
    local.common_tags,
    each.value.tags != null ? each.value.tags : {},
    # each.value.application_insights != null ? {
    #   "hidden-link: /app-insights-conn-string"         = sensitive(data.azurerm_application_insights.default[each.value.application_insights].connection_string)
    #   "hidden-link: /app-insights-instrumentation-key" = sensitive(data.azurerm_application_insights.default[each.value.application_insights].instrumentation_key)
    #   "hidden-link: /app-insights-resource-id"         = data.azurerm_application_insights.default[each.value.application_insights].id
    # } : {},
    each.value.allow_front_door_access_restriction_front_door_id != null ? {
      "frontdoor" = "true",
      "hardened"  = "true"
      } : {
      "frontdoor" = "false",
      "hardened"  = "false"
    },
    # lookup(each.value.application_stack, "continuous_deployment", null) == true ? {
    #   "hidden-link: acrResourceId" = jsonencode({ subscriptionId = data.azurerm.xxxxxxxxx})
    # } : {}
  )

  lifecycle {
    ignore_changes = [
      #connection_string,
      #app_settings,
      #sticky_settings,
      #site_config[0].application_stack
    ]
  }
}

# ===================== SSL Certificates and Custom Domains =====================
// Linux app custom domain binding
resource "azurerm_app_service_custom_hostname_binding" "linux_webapp" {
  for_each = {
    for item in local.linux_web_apps_with_domains :
    "${item.app_key}-${item.domain}" => item
  }

  hostname            = each.value.domain
  resource_group_name = azurerm_resource_group.this.name
  app_service_name    = azurerm_linux_web_app.this[each.value.app_key].name
}

data "azurerm_key_vault" "linux_key_vault_as_secret" {
  for_each = {
    for k, v in local.key_vault_certificates : k => v if v.secret_name != null
  }

  name                = split("/", each.value.key_vault_id)[8]
  resource_group_name = split("/", each.value.key_vault_id)[4]
}

data "azurerm_key_vault" "linux_key_vault_as_certificate" {
  for_each = {
    for k, v in local.key_vault_certificates : k => v if v.certificate_name != null
  }

  name                = split("/", each.value.key_vault_id)[8]
  resource_group_name = split("/", each.value.key_vault_id)[4]
}

data "azurerm_key_vault_secret" "linux_web_app_certificate_secret" {
  for_each = {
    for k, v in local.key_vault_certificates : k => v if v.secret_name != null
  }

  name         = each.value.secret_name
  key_vault_id = data.azurerm_key_vault.linux_key_vault_as_secret[each.key].id
}

data "azurerm_key_vault_secret" "linux_web_app_certificate_certificate" {
  for_each = {
    for k, v in local.key_vault_certificates : k => v if v.certificate_name != null
  }

  name         = each.value.certificate_name
  key_vault_id = data.azurerm_key_vault.linux_key_vault_as_certificate[each.key].id
}

# Certificate resource as secret
resource "azurerm_app_service_certificate" "app_service_certificate_as_secret" {
  for_each = {
    for k, v in local.key_vault_certificates : k => v if v.secret_name != null
  }

  name                = each.value.name != null ? each.value.name : "${each.value.key}-${each.value.location}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.this.name
  key_vault_secret_id = data.azurerm_key_vault_secret.linux_web_app_certificate_secret[each.key].versionless_id

  tags = merge(
    local.common_tags,
    each.value.tags != null ? each.value.tags : {}
  )
}

# Certificate resource as certificate
resource "azurerm_app_service_certificate" "app_service_certificate_as_certificate" {
  for_each = {
    for k, v in local.key_vault_certificates : k => v if v.certificate_name != null
  }

  name                = each.value.name != null ? each.value.name : "${each.value.key}-${each.value.location}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.this.name
  pfx_blob            = data.azurerm_key_vault_secret.linux_web_app_certificate_certificate["${each.value.location}.${each.value.certificate_name}"].value

  tags = merge(
    local.common_tags,
    each.value.tags != null ? each.value.tags : {}
  )
}

# Linux Web App Certificate binding resouces for certificates as secrets and as certificates
resource "azurerm_app_service_certificate_binding" "linux_key_vault_certificate_as_secret" {
  for_each = {
    for item in local.linux_web_apps_with_key_vault_certificates :
    "${item.app_key}-${item.domain}" => item
    if item.secret_name != null
  }

  hostname_binding_id = azurerm_app_service_custom_hostname_binding.linux_webapp[each.key].id
  certificate_id      = azurerm_app_service_certificate.app_service_certificate_as_secret[each.value.certificate_full_key].id
  ssl_state           = "SniEnabled"

  depends_on = [
    azurerm_app_service_certificate.app_service_certificate_as_secret
  ]
}

# Linux Web App Certificate resource as certificate
resource "azurerm_app_service_certificate_binding" "linux_key_vault_certificate_as_certificate" {
  for_each = {
    for item in local.linux_web_apps_with_key_vault_certificates :
    "${item.app_key}-${item.domain}" => item
    if item.certificate_name != null
  }

  hostname_binding_id = azurerm_app_service_custom_hostname_binding.linux_webapp[each.key].id
  certificate_id      = azurerm_app_service_certificate.app_service_certificate_as_certificate[each.value.certificate_full_key].id
  ssl_state           = "SniEnabled"

  depends_on = [
    azurerm_app_service_certificate.app_service_certificate_as_certificate
  ]
}

# Provide access to the web app's managed identity to the key vault if there are any app settings referencing key vault secrets
resource "azurerm_role_assignment" "webapp_kv_app_settings_access" {
  for_each = local.webapp_kv_app_settings_role_assignments

  scope                = each.value.key_vault_key != null ? azurerm_key_vault.this[each.value.key_vault_key].id : each.value.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.this[each.value.app_name].identity[0].principal_id

  description          = "Granted by module terraform-azure-module for app settings reference to key vault secrets in web app ${var.project_name}-${each.value.app_name}"

  depends_on = [azurerm_linux_web_app.this]
}

# Diagnostic settings for Linux web apps
resource "azurerm_monitor_diagnostic_setting" "linux_webapp_diagnostic" {
  for_each = local.app_service_webapp_diagnostic_settings

  name               = each.value.name != null ? each.value.name : "${var.project_name}-${each.value.web_app}-${var.environment}-${local.location_abbreviation}-${each.value.key}-diagnostic"
  target_resource_id = azurerm_linux_web_app.this[each.value.web_app].id

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

  depends_on = [azurerm_linux_web_app.this]
}

# =================== Github Integration ===================
# Create a user-assigned managed identity for the github integration
resource "azurerm_user_assigned_identity" "github_integration" {
  for_each = var.web_apps != null ? {
    for k, v in var.web_apps : k => v
    if v.source_control != null && v.source_control != null && v.source_control.type == "GitHub"
  } : {}

  name                = each.value.name != null ? each.value.name : lower("${var.project_name}-${each.value.key != null ? each.value.key : each.key}-${var.environment}-${local.location_abbreviation_app_service_plan[each.value.app_service_plan]}-github-integration")
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  tags = merge(
    local.common_tags,
    each.value.tags != null ? each.value.tags : {}
  )
}

# Github OIDC federated credential for the web app's github UAMI
resource "azurerm_federated_identity_credential" "github_integration" {
  for_each = var.web_apps != null ? {
    for k, v in var.web_apps : k => v
    if v.source_control != null && v.source_control != null && v.source_control.type == "GitHub"
  } : {}

  name                      = "${var.project_name}-${each.key}-${var.environment}-oidc-federated-credential"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_integration[each.key].id
  subject                   = "repo:${replace(each.value.source_control.repo_url, "https://github.com/", "")}:ref:refs/heads/${each.value.source_control.branch}"
}

# Also the user managed identity will need website contributor for the web app
resource "azurerm_role_assignment" "github_integration" {
  for_each = var.web_apps != null ? {
    for k, v in var.web_apps : k => v
    if v.source_control != null && v.source_control != null && v.source_control.type == "GitHub"
  } : {}

  principal_id         = azurerm_user_assigned_identity.github_integration[each.key].principal_id
  role_definition_name = "Website Contributor"
  scope                = azurerm_linux_web_app.this[each.key].id
}

# ================= Source Control Integration =================
resource "azurerm_app_service_source_control" "this" {
  for_each = var.web_apps != null ? {
    for k, v in var.web_apps : k => v
    if v.source_control != null && v.source_control != null
  } : {}

  app_id                 = azurerm_linux_web_app.this[each.key].id
  repo_url               = each.value.source_control["repo_url"]
  branch                 = each.value.source_control["branch"] != null ? each.value.source_control["branch"] : null
  use_manual_integration = each.value.source_control["use_manual_integration"] != null ? each.value.source_control["use_manual_integration"] : false

  dynamic "github_action_configuration" {
    for_each = each.value.source_control.type == "GitHub" && each.value.source_control.github_action_configuration != null ? [each.value.source_control.github_action_configuration] : []

    content {
      generate_workflow_file = github_action_configuration.value.generate_workflow_file

      dynamic "code_configuration" {
        for_each = local.webapp_github_code_config[each.key] != null ? [local.webapp_github_code_config[each.key]] : []

        content {
          runtime_stack   = code_configuration.value.runtime_stack
          runtime_version = code_configuration.value.runtime_version
        }
      }

      dynamic "container_configuration" {
        for_each = github_action_configuration.value.container_configuration != null ? [github_action_configuration.value.container_configuration] : []

        content {
          image_name   = container_configuration.value.image_name
          registry_url = container_configuration.value.registry_url
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      github_action_configuration
    ]
  }

  depends_on = [
    azurerm_linux_web_app.this,
    #azurerm_source_control_token.this # Ensure the source control token is created before the source control integration
  ]
}

# ===================== VNet Integration =====================
# resource "azurerm_app_service_virtual_network_swift_connection" "default" {
#   for_each = var.web_apps != null ? {
#     for k, v in var.web_apps : k => v
#     if v.vnet_integration != null && var.vnet != null
#   } : {}

#   app_service_id = azurerm_linux_web_app.this[each.key].id
#   subnet_id      = data.azurerm_subnet.webapps_vnet_integration[each.key].id
# }



# ACR hook and acr pull
# resource "azurerm_container_registry_webhook" "linux_webapp_webhook" {
#   for_each = var.web_apps != null && var.app_service_plans != null ? {
#     for k, v in var.web_apps : k => v
#     if lookup(var.app_service_plans, v.app_service_plan, null) != null &&
#     var.app_service_plans[v.app_service_plan].os_type == "Linux" &&
#     lookup(v.application_stack, "continuous_deployment", false) == true
#   } : {}

#   name                = "${replace(var.project_name, "-", "")}${replace(each.key, "-", "")}${var.environment}"
#   location            = data.azurerm_container_registry.acr[each.key].location
#   resource_group_name = data.azurerm_container_registry.acr[each.key].resource_group_name
#   registry_name       = data.azurerm_container_registry.acr[each.key].name
#   service_uri         = "https://${azurerm_linux_web_app.this[each.key].site_credential.0.name}:${azurerm_linux_web_app.this[each.key].site_credential.0.password}@${azurerm_linux_web_app.this[each.key].name}.scm.azurewebsites.net/api/registry/webhook" # Thanks to https://stackoverflow.com/questions/75307946/terraform-azure-how-to-get-deployment-webhook-url
#   actions             = ["push"]
#   scope               = each.value.application_stack["docker_image_name"] #"${split(":", each.value.application_stack["docker_image_name"])[0]}:*"
# }


# Now provide acr pull permissions to the web app if container_registry_use_managed_identity is true
# resource "azurerm_role_assignment" "linux_webapp_acr_pull" {
#   for_each = var.web_apps != null && var.app_service_plans != null ? {
#     for k, v in var.web_apps : k => v
#     if lookup(v.application_stack, "docker_registry_url", null) != null && 
#     lookup(v.site_config, "container_registry_use_managed_identity", false) == true && 
#     lookup(var.app_service_plans, v.app_service_plan, null) != null &&
#     var.app_service_plans[v.app_service_plan].os_type == "Linux"
#   } : {}

#   scope                = data.azurerm_container_registry.acr[each.key].id
#   role_definition_name = "AcrPull"
#   principal_id         = azurerm_linux_web_app.this[each.key].identity[0].principal_id

#   depends_on = [
#     azurerm_linux_web_app.this
#   ]
# }

resource "azurerm_monitor_activity_log_alert" "resource_health_alert" {
  for_each = var.web_apps != null ? {
    for k, v in var.web_apps :
    k => v
    if try(v.alert_rules.resource_health, null) != null
  } : {}

  name                = "resource-health-${azurerm_linux_web_app.this[each.key].name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = "global"
  scopes              = [azurerm_linux_web_app.this[each.key].id]
  description         = "Resource Health alert for ${azurerm_linux_web_app.this[each.key].name}"
  enabled             = each.value.alert_rules.resource_health.enabled

  criteria {
    category = "ResourceHealth"
    # Only "category" and optionally "level" and "resource_id" are supported here
  }

  action {
    action_group_id = each.value.alert_rules.resource_health.action_group_id
  }

  tags = merge(
    local.common_tags,
    {
      "webapp_name" = azurerm_linux_web_app.this[each.key].name
    }
  )
}

