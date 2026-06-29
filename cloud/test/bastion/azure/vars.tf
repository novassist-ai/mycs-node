#
# Azure region
#
variable "region" {
  type = string
}

#
# MyCS Node IdKey
#
variable "mycs_node_private_key" {
  default = ""
}

variable "mycs_node_id_key" {
  default = ""
}

#
# SMTP settings for notifications
#

variable "smtp_relay_host" {
  default = ""
}

variable "smtp_relay_port" {
  default = ""
}

variable "smtp_relay_api_key" {
  default = ""
}

variable "notification_email" {
  default = ""
}

#
# Bastion Image
#

variable "bastion_use_managed_image" {
  type = bool
}

variable "bastion_image_name" {
  type = string
}

variable "bastion_image_storage_account_prefix" {
  default = "abi"
}

#
# Networking
#

variable "attach_dns_zone" {
  type = string
}

variable "configure_admin_network" {
  type = string
}

#
# Distinct CIDR for VPCs by region
#
variable "regional_vpc_cidr" {
  default = {
    westus = {
      vpc_cidr = "172.20.0.0/22"
    }
    westus2 = {
      vpc_cidr = "172.20.4.0/22"
    }
    westcentralus = {
      vpc_cidr = "172.20.8.0/22"
    }
    northcentralus = {
      vpc_cidr = "172.20.12.0/22"
    }
    centralus = {
      vpc_cidr = "172.20.16.0/22"
    }
    southcentralus = {
      vpc_cidr = "172.20.20.0/22"
    }
    eastus = {
      vpc_cidr = "172.20.24.0/22"
    }
    eastus2 = {
      vpc_cidr = "172.20.28.0/22"
    }
    canadacentral = {
      vpc_cidr = "172.20.32.0/22"
    }
    canadaeast = {
      vpc_cidr = "172.20.36.0/22"
    }
    brazilsouth = {
      vpc_cidr = "172.20.40.0/22"
    }
    ukwest = {
      vpc_cidr = "172.20.44.0/22"
    }
    uksouth = {
      vpc_cidr = "172.20.48.0/22"
    }
    francecentral = {
      vpc_cidr = "172.20.52.0/22"
    }
    francesouth = {
      vpc_cidr = "172.20.56.0/22"
    }
    westeurope = {
      vpc_cidr = "172.20.60.0/22"
    }
    northeurope = {
      vpc_cidr = "172.20.64.0/22"
    }
    norwaywest = {
      vpc_cidr = "172.20.68.0/22"
    }
    norwayeast = {
      vpc_cidr = "172.20.72.0/22"
    }
    switzerlandwest = {
      vpc_cidr = "172.20.76.0/22"
    }
    switzerlandnorth = {
      vpc_cidr = "172.20.80.0/22"
    }
    germanywestcentral = {
      vpc_cidr = "172.20.84.0/22"
    }
    germanynorth = {
      vpc_cidr = "172.20.88.0/22"
    }
    southafricawest = {
      vpc_cidr = "172.20.92.0/22"
    }
    southafricanorth = {
      vpc_cidr = "172.20.96.0/22"
    }
    uaecentral = {
      vpc_cidr = "172.20.100.0/22"
    }
    uaenorth = {
      vpc_cidr = "172.20.104.0/22"
    }
    westindia = {
      vpc_cidr = "172.20.108.0/22"
    }
    centralindia = {
      vpc_cidr = "172.20.112.0/22"
    }
    southindia = {
      vpc_cidr = "172.20.116.0/22"
    }
    eastasia = {
      vpc_cidr = "172.20.120.0/22"
    }
    southeastasia = {
      vpc_cidr = "172.20.124.0/22"
    }
    koreacentral = {
      vpc_cidr = "172.20.128.0/22"
    }
    koreasouth = {
      vpc_cidr = "172.20.132.0/22"
    }
    japanwest = {
      vpc_cidr = "172.20.136.0/22"
    }
    japaneast = {
      vpc_cidr = "172.20.140.0/22"
    }
    australiacentral = {
      vpc_cidr = "172.20.144.0/22"
    }
    australiacentral2 = {
      vpc_cidr = "172.20.148.0/22"
    }
    australiaeast = {
      vpc_cidr = "172.20.152.0/22"
    }
    australiasoutheast = {
      vpc_cidr = "172.20.156.0/22"
    }
  }
}
