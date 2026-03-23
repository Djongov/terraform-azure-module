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
  type    = map(string)
  default = {}
}

variable "storage_accounts" {
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