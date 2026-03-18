locals {
    common_tags = merge({
            "managed-by" = "terraform",
            "environment" = var.environment,
            "project" = var.project_name
        },
        var.common_tags
    )

    location_abbreviations = {
    # Europe
    "West Europe"          = "we"
    "westeurope"           = "we"
    "North Europe"         = "ne"
    "northeurope"          = "ne"
    "France Central"       = "fc"
    "francecentral"        = "fc"
    "France South"         = "fs"
    "francesouth"          = "fs"
    "Germany West Central" = "gwc"
    "germanywestcentral"   = "gwc"
    "Germany North"        = "gn"
    "germanynorth"         = "gn"
    "Norway East"          = "noe"
    "norwayeast"           = "noe"
    "Norway West"          = "now"
    "norwaywest"           = "now"
    "Sweden Central"       = "sec"
    "swedencentral"        = "sec"
    "Sweden South"         = "ses"
    "swedensouth"          = "ses"
    "Switzerland North"    = "sn"
    "switzerlandnorth"     = "sn"
    "Switzerland West"     = "sww"
    "switzerlandwest"      = "sww"
    "UK South"             = "uks"
    "uksouth"              = "uks"
    "UK West"              = "ukw"
    "ukwest"               = "ukw"
  }

  # We can use this to get the location abbreviation from the location name, use it to name resources
  location_abbreviation = lookup(local.location_abbreviations, var.location, "")
}