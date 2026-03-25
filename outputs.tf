output "static_web_app_api_keys" {
  description = "API keys for each Static Web App, used for CI/CD deployments."
  value       = { for k, v in azurerm_static_web_app.this : k => v.api_key }
  sensitive   = true
}
