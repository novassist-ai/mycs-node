#
# Google compute region
#
variable "region" {
  type = string
}

variable "time_zone" {
  default = "Etc/UTC"
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
# Resource group containing resources 
# required to build the VPC
#
variable "source_resource_group" {
  type = string
}

#
# VPC and network variables
#
variable "vpc_name" {
  type = string
}

# VPC DNS zone
variable "vpc_dns_zone" {
  type = string
}

# Attach DNS to parent zone. This 
# requires the parent zone to exist 
# within the same cloud provider.
# Otherwise once deployed the VPC
# zone's nameservers need to be added
# manually to the parent zone.
variable "attach_dns_zone" {
  default = false
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
  default = ""
}

variable "admin_cidr" {
  default = ""
}

variable "max_azs" {
  default = 1
}

# Internal CIDR for all VPC address 
# spaces across all regions
variable "global_internal_cidr" {
  default = ""
}

#
# Bastion inception instance variables
#
variable "bastion_instance_type" {
  default = "Standard_DS2_v2"
}

variable "bastion_use_managed_image" {
  default = true
}

variable "bastion_image_name" {
  default = "appbricks-bastion_dev"
}

variable "bastion_image_storage_account_prefix" {
  default = "mycs"
}

variable "bastion_image_container" {
  default = "nodeimage"
}

variable "bastion_root_disk_size" {
  default = 30
}

variable "bastion_data_disk_size" {
  default = 5
}

variable "bastion_host_name" {
  default = ""
}

variable "bastion_use_fqdn" {
  default = true
}

# Note: this has no effect on azure
# as you cannot create an explicit
# rule for ICMP.
variable "allow_bastion_icmp" {
  default = false
}

#
# Configure admin network segment.
#
variable "configure_admin_network" {
  default = false
}

#
# Certify bastion host using letsencrypt certificates
#
variable "certify_bastion" {
  default = false
}

#
# DNS resolvers for the  server
#
variable "bastion_dns" {
  # see: https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
  default = "168.63.129.16"
}

#
# Bastion access configuration
#
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
  # one of "wireguard", "openvpn" or "ipsec"
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
# Wireguard configuration
#
variable "wireguard_service_port" {
  default = ""
}

variable "wireguard_mesh_network" {
  default = "192.168.112.0/24"
}

variable "wireguard_mesh_node" {
  default = 1
}

#
# UDP port of mycs-node DERP STUN service
#
variable "derp_stun_port" {
  default = ""
}

#
# OpenVPN configuration
#
variable "ovpn_service_port" {
  default = ""
}

variable "ovpn_protocol" {
  default = "udp"
}

#
# Enable tunnelling of VPN within another tunnel 
# when firewalls and telco's block OpenVPN via
# deep-packet-inspection.
#
variable "tunnel_vpn_port_start" {
  default = ""
}

variable "tunnel_vpn_port_end" {
  default = ""
}

variable "vpn_gateway_peer_config_paths" {
  type        = list(string)
  default     = []
  description = "Local paths to peer YAML files uploaded to /usr/local/etc/vpn-gw-peers/ on the bastion at first boot."
}

variable "vpn_gateway_peer_file_contents" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = "Peer YAML filename => content for cloud-init upload when content is Terraform-rendered."
}

#
# Configure SMTP
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

#
# Squid Proxy port
#
variable "squidproxy_server_port" {
  default = ""
}

#
# Jumpbox
#
variable "deploy_jumpbox" {
  default = true
}

variable "jumpbox_data_disk_size" {
  default = "160"
}
