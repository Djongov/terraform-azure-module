variable "subscription_id" {}
variable "environment" {}
variable "location" {}
variable "project_name" {}
variable "common_tags" {}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

module "resource_group" {
  source = "../../"

  project_name    = var.project_name
  environment     = var.environment
  location        = var.location
  subscription_id = var.subscription_id
  common_tags     = var.common_tags
}