#
# OpenStack region (OVHcloud Public Cloud region code, e.g. UK1, GRA9)
#
variable "region" {
  type = string
}

variable "time_zone" {
  default = "Etc/UTC"
}

#
# Provider external network (OVH Public Cloud: Ext-Net)
#
variable "external_network_name" {
  default = "Ext-Net"
}

#
# MyCloudSpace node service keys
#
variable "mycs_node_private_key" {
  default = ""
}

variable "mycs_node_id_key" {
  default = ""
}

variable "mycs_node_id" {
  default = ""
}

#
# Certificate Subject data for certificate creation
#
variable "company_name" {
  type = string
}

variable "organization_name" {
  type = string
}

variable "locality" {
  type = string
}

variable "province" {
  type = string
}

variable "country" {
  type = string
}

#
# Root CA key and cert to use for signing self signed certificates
#
variable "root_ca_key" {
  default = ""
}

variable "root_ca_cert" {
  default = ""
}

#
# VPC and network variables
#
variable "vpc_name" {
  type = string
}

variable "vpc_dns_zone" {
  type = string
}

variable "attach_dns_zone" {
  default = false
}

#
# External DNS via AWS Route53 (OpenStack has no native DNS API).
# Set dns_provider to aws when attach_dns_zone is true.
#
variable "dns_provider" {
  type        = string
  default     = ""
  description = "External DNS provider. OpenStack bootstrap supports aws or empty."

  validation {
    condition     = contains(["", "aws"], var.dns_provider)
    error_message = "dns_provider must be empty or aws for OpenStack bootstrap."
  }
}

variable "dns_parent_zone_name" {
  default     = ""
  description = "Parent DNS zone for NS delegation (e.g. ovh.appbricks.io). Defaults from vpc_dns_zone."
}

variable "vpc_cidr" {
  default = "172.16.0.0/16"
}

variable "vpc_subnet_bits" {
  default = 4
}

variable "vpc_subnet_start" {
  default = 1
}

variable "vpc_internal_dns_zones" {
  default = [""]
}

variable "vpc_internal_dns_records" {
  default = []
}

variable "dmz_cidr" {
  default = []
}

variable "admin_cidr" {
  default = []
}

variable "admin_vlan_id" {
  default     = -1
  description = "vRack VLAN ID for the admin LAN. 0 keeps the admin subnet on the main VPC network."
}

variable "max_azs" {
  default = 1
}

variable "global_internal_cidr" {
  default = ""
}

#
# Bastion inception instance variables
#
variable "bastion_flavor" {
  default = "d2-2"
}

variable "bastion_image_name_regex" {
  type        = string
  description = "Regex to select the bastion Glance image (most recent match is used)."
}

variable "bastion_root_disk_size" {
  default     = 25
  description = "Root boot volume size in GB."
}

variable "bastion_data_disk_size" {
  default = 10
}

variable "bastion_data_disk_device_name" {
  default = "vdb"
}

variable "bastion_host_name" {
  default = ""
}

variable "bastion_use_fqdn" {
  default = true
}

variable "allow_bastion_icmp" {
  default = false
}

variable "bastion_as_nat" {
  default = true
}

variable "configure_admin_network" {
  default = false
}

variable "certify_bastion" {
  default = false
}

variable "bastion_dns" {
  default = ""
}

variable "bastion_admin_api_port" {
  default = "443"
}

variable "bastion_admin_ssh_port" {
  default = "22"
}

variable "bastion_admin_user" {
  default = "bastion-admin"
}

variable "bastion_allow_public_ssh" {
  default = true
}

#
# VPN configuration
#
variable "vpn_type" {
  default = ""
}

variable "vpn_network" {
  default = "192.168.111.0/24"
}

variable "vpn_protected_sub_range" {
  default = 2
}

variable "vpn_tunnel_all_traffic" {
  default = "no"
}

variable "vpn_idle_action" {
  default = "none"
}

variable "vpn_idle_shutdown_time" {
  default = 10
}

variable "vpn_users" {
  default = []
}

#
# Optional upstream VPN gateway (site-to-site IPsec).
# Peer-specific settings are managed via manage_vpn_gateway_peer at runtime.
#
variable "vpn_gateway_enabled" {
  default = false
}

variable "vpn_gateway_protocol" {
  default = "ipsec"
}

variable "vpn_gateway_peer_cidrs" {
  type        = list(string)
  default     = []
  description = "Remote VPN peer admin CIDRs allowed into the internal security group when bastion_as_nat is true."
}

variable "vpn_gateway_peer_export_path" {
  type        = string
  default     = ""
  description = "When set, write this bastion's VPN gateway peer export YAML to this path."
}

variable "wireguard_service_port" {
  default = ""
}

variable "wireguard_mesh_network" {
  default = "192.168.112.0/24"
}

variable "wireguard_mesh_node" {
  default = 1
}

variable "derp_stun_port" {
  default = ""
}

variable "ovpn_service_port" {
  default = ""
}

variable "ovpn_protocol" {
  default = "udp"
}

variable "tunnel_vpn_port_start" {
  default = ""
}

variable "tunnel_vpn_port_end" {
  default = ""
}

variable "smtp_relay_host" {
  default = ""
}

variable "smtp_relay_port" {
  default = ""
}

variable "smtp_relay_api_key" {
  default = ""
}

variable "squidproxy_server_port" {
  default = ""
}

#
# Jumpbox
#
variable "deploy_jumpbox" {
  default = true
}

variable "jumpbox_image_name" {
  default = "Ubuntu 24.04"
}

variable "jumpbox_flavor" {
  default = "d2-2"
}

variable "jumpbox_data_disk_size" {
  default = "160"
}

variable "jumpbox_data_disk_device_name" {
  default = "vdb"
}
