output "linux_web_app_acr_webhook_uris" {
  description = "Webhook service URIs for web apps using a cross-subscription ACR (acr_location is set). Register these as webhooks on the ACR manually or via a separate provider."
  value = var.web_apps != null ? {
    for k, v in var.web_apps :
    k => "https://${azurerm_linux_web_app.this[k].site_credential.0.name}:${azurerm_linux_web_app.this[k].site_credential.0.password}@${azurerm_linux_web_app.this[k].name}.scm.azurewebsites.net/api/registry/webhook"
    if lookup(v.application_stack, "acr_id", null) != null &&
    lookup(v.application_stack, "acr_location", null) != null &&
    lookup(v.application_stack, "continuous_deployment", false) == true
  } : {}

  sensitive = true
}

output "linux_web_app_custom_domain_cname_records" {
  description = "CNAME records to create in DNS for each custom domain: map of custom_domain => default hostname of the web app."
  value = {
    for item in local.linux_web_apps_with_domains :
    item.domain => azurerm_linux_web_app.this[item.app_key].default_hostname
  }
}

output "linux_web_app_custom_domain_verification_txt_records" {
  description = "TXT records to create in DNS for custom domain ownership verification: map of asuid.<custom_domain> => custom_domain_verification_id of the web app."
  value = {
    for item in local.linux_web_apps_with_domains :
    "asuid.${item.domain}" => azurerm_linux_web_app.this[item.app_key].custom_domain_verification_id
  }
  sensitive = true
}
