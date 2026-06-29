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
# Google Cloud Platform region
#
variable "region" {
  type = string
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

variable "bastion_use_project_image" {
  type = bool
}

variable "bastion_image_name" {
  type = string
}

variable "bastion_image_bucket_prefix" {
  default = "abimages"
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
    # The Dalles, Oregon, USA
    us-west1 = {
      vpc_cidr = "172.20.0.0/22"
    }
    # Los Angeles, California, USA
    us-west2 = {
      vpc_cidr = "172.20.4.0/22"
    }
    # Council Bluffs, Iowa, USA
    us-central1 = {
      vpc_cidr = "172.20.8.0/22"
    }
    # Ashburn, Northern Virginia, USA
    us-east4 = {
      vpc_cidr = "172.20.12.0/22"
    }
    # Moncks Corner, South Carolina, USA
    us-east1 = {
      vpc_cidr = "172.20.16.0/22"
    }
    # Montréal, Québec, Canada
    northamerica-northeast1 = {
      vpc_cidr = "172.20.20.0/22"
    }
    # Osasco (São Paulo), Brazil
    southamerica-east1 = {
      vpc_cidr = "172.20.24.0/22"
    }
    # St. Ghislain, Belgium
    europe-west1 = {
      vpc_cidr = "172.20.28.0/22"
    }
    # London, England, UK
    europe-west2 = {
      vpc_cidr = "172.20.32.0/22"
    }
    # Frankfurt, Germany
    europe-west3 = {
      vpc_cidr = "172.20.36.0/22"
    }
    # Eemshaven, Netherlands
    europe-west4 = {
      vpc_cidr = "172.20.40.0/22"
    }
    # Zürich, Switzerland
    europe-west6 = {
      vpc_cidr = "172.20.44.0/22"
    }
    # Hamina, Finland
    europe-north1 = {
      vpc_cidr = "172.20.48.0/22"
    }
    # Mumbai, India
    asia-south1 = {
      vpc_cidr = "172.20.52.0/22"
    }
    # Changhua County, Taiwan
    asia-east1 = {
      vpc_cidr = "172.20.60.0/22"
    }
    # Hong Kong
    asia-east2 = {
      vpc_cidr = "172.20.64.0/22"
    }
    # Tokyo, Japan
    asia-northeast1 = {
      vpc_cidr = "172.20.68.0/22"
    }
    # Osaka, Japan
    asia-northeast2 = {
      vpc_cidr = "172.20.72.0/22"
    }
    # Jurong West, Singapore
    asia-southeast1 = {
      vpc_cidr = "172.20.76.0/22"
    }
    # Sydney, Australia
    australia-southeast1 = {
      vpc_cidr = "172.20.80.0/22"
    }
  }
}
