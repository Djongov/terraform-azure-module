terraform {
  required_version = ">= 1.10.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.64.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "= 3.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.5.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "= 0.13.1"
    }
  }
}
