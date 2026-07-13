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
# Bastion Image (built via bastion-image/build/build-ovh-image.sh)
#
variable "bastion_image_name_regex" {
  type = string
}

variable "bastion_flavor" {
  default = "d2-2"
}

#
# OpenStack / OVHcloud
#
variable "region" {
  type = string
}

variable "external_network_name" {
  default = "Ext-Net"
}

variable "attach_dns_zone" {
  type = string
}

variable "bastion_dns" {
  type = string
}

#
# External DNS via AWS Route53 for the OpenStack VPC zone
#
variable "dns_parent_zone_name" {
  default     = ""
  description = "Parent DNS zone for NS delegation. Defaults to ovh.appbricks.io from vpc_dns_zone."
}

variable "aws_dns_region" {
  default     = "us-east-1"
  description = "AWS region for Route53 API (where the parent zone is hosted)."
}

variable "configure_admin_network" {
  type = string
}

variable "vpn_gateway_peer_config_paths" {
  type        = list(string)
  default     = []
  description = "Local paths to peer YAML files uploaded to the bastion at first boot via cloud-init."
}

#
# Distinct CIDR for VPCs by OVH region
#
variable "regional_vpc_cidr" {
  default = {
    UK1 = {
      vpc_cidr = "172.20.64.0/22"
    }
    GRA9 = {
      vpc_cidr = "172.20.68.0/22"
    }
    SBG5 = {
      vpc_cidr = "172.20.72.0/22"
    }
    DE1 = {
      vpc_cidr = "172.20.76.0/22"
    }
    WAW1 = {
      vpc_cidr = "172.20.80.0/22"
    }
    BHS5 = {
      vpc_cidr = "172.20.84.0/22"
    }
  }
}
