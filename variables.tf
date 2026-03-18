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