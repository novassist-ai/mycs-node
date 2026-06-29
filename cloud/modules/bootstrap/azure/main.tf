#
# Local declarations
#

locals {

  # Not all regions support all azure storage. The
  # map below maps regions to the regions which
  # have supported storage capability.
  storage_supported_regions = {
    "australiacentral": "australiacentral",
    "australiacentral2": "australiacentral",
    "australiaeast": "australiaeast",
    "australiasoutheast": "australiasoutheast",
    "brazilsouth": "brazilsouth",
    "canadacentral": "canadacentral",
    "canadaeast": "canadaeast",
    "centralindia": "centralindia",
    "centralus": "centralus",
    "eastasia": "eastasia",
    "eastus": "eastus",
    "eastus2": "eastus2",
    "francecentral": "francecentral",
    "francesouth": "francecentral",
    "germanynorth": "francecentral",
    "germanywestcentral": "francecentral",
    "japaneast": "japaneast",
    "japanwest": "japanwest",
    "koreacentral": "koreacentral",
    "koreasouth": "koreasouth",
    "northcentralus": "northcentralus",
    "northeurope": "northeurope",
    "norwayeast": "francecentral",
    "norwaywest": "francecentral",
    "southafricanorth": "southafricanorth",
    "southafricawest": "southafricanorth",
    "southcentralus": "southcentralus",
    "southeastasia": "southeastasia",
    "southindia": "southindia",
    "switzerlandnorth": "francecentral",
    "switzerlandwest": "francecentral",
    "uaecentral": "uaenorth",
    "uaenorth": "uaenorth",
    "uksouth": "uksouth",
    "ukwest": "ukwest",
    "westcentralus": "westcentralus",
    "westeurope": "westeurope",
    "westindia": "westindia",
    "westus": "westus",
    "westus2": "westus2",
  }

  storage_region = local.storage_supported_regions[var.region]
}

#
# The VPC's Bootstrap resource group
#
resource "azurerm_resource_group" "bootstrap" {
  name     = var.vpc_name
  location = local.storage_region
}

data "azurerm_resource_group" "source" {
  name = var.source_resource_group
}

#
# The VPC's Storage Account
#
resource "azurerm_storage_account" "bootstrap-storage-account" {
  name = "stacct${random_string.bootstrap-storage-account-key.result}"

  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name

  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "random_string" "bootstrap-storage-account-key" {
  length = 18
  upper = false
  special = false
}

#
# Default SSH Key Pair
#
resource "tls_private_key" "default-ssh-key" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

