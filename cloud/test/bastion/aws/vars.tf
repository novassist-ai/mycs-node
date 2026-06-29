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

variable "bastion_image_name" {
  type = string
}

variable "bastion_image_owner" {
  type = string
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
    # US West (N. California)
    us-west-1 = {
      vpc_cidr = "172.20.0.0/22"
    }
    # US West (Oregon)
    us-west-2  = {
      vpc_cidr = "172.20.4.0/22"
    }
    # US East (N. Virginia)
    us-east-1 = {
      vpc_cidr = "172.20.8.0/22"
    }
    # US East (Ohio)
    us-east-2 = {
      vpc_cidr = "172.20.12.0/22"
    }
    # Canada (Central)
    ca-central-1 = {
      vpc_cidr = "172.20.16.0/22"
    }
    # South America (Sao Paulo)
    sa-east-1 = {
      vpc_cidr = "172.20.20.0/22"
    }
    # EU (Ireland)
    eu-west-1 = {
      vpc_cidr = "172.20.24.0/22"
    }
    # EU (London)
    eu-west-2 = {
      vpc_cidr = "172.20.28.0/22"
    }
    # EU (Paris)
    eu-west-3 = {
      vpc_cidr = "172.20.32.0/22"
    }
    # EU (Frankfurt)
    eu-central-1 = {
      vpc_cidr = "172.20.36.0/22"
    }
    # EU (Stockholm)
    eu-north-1 = {
      vpc_cidr = "172.20.40.0/22"
    }
    # Asia Pacific (Mumbai)
    ap-south-1 = {
      vpc_cidr = "172.20.44.0/22"
    }
    # Asia Pacific (Tokyo)
    ap-northeast-1 = {
      vpc_cidr = "172.20.48.0/22"
    }
    # Asia Pacific (Seoul)
    ap-northeast-2 = {
      vpc_cidr = "172.20.52.0/22"
    }
    # Asia Pacific (Singapore)
    ap-southeast-1 = {
      vpc_cidr = "172.20.56.0/22"
    }
    # Asia Pacific (Sydney)
    ap-southeast-2 = {
      vpc_cidr = "172.20.60.0/22"
    }
  }
}
