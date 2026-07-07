#
# Locale
#
variable "time_zone" {
  default = "Etc/UTC"
}

#
# MyCloudSpace node service keys
#
variable "mycs_node_private_key" {
  type = string
}

variable "mycs_node_id_key" {
  type = string
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
  type = string
}

variable "root_ca_cert" {
  type = string
}

#
# List of DNS names to associate bastion cert with
#
variable "cert_domain_names" {
  type = list(any)
}

#
# VPC and network variables
#
variable "vpc_name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "vpc_dns_zone" {
  type = string
}

variable "vpc_internal_dns_zones" {
  type = list(any)
}

variable "vpc_internal_dns_records" {
  type = list(any)
}

#
# Bastion inception instance network configuration
#
variable "bastion_fqdn" {
  type = string
}

variable "bastion_use_fqdn" {
  type = bool
}

variable "bastion_public_ip" {
  type = string
}

#
# Certify bastion host using letsencrypt certificates
#
variable "certify_bastion" {
  default = false
}

#
# DNS resolvers for the Bastion server
#
variable "bastion_dns" {
  type = string
}

#
# Setup bastion as a DHCP server for LANs
#

variable "enable_bastion_as_dhcpd" {
  default = false
}

variable "dhcpd_lease_range" {
  default = "50"
}

# The local IP of the external or NAT interface
variable "bastion_dmz_itf_ip" {
  type = string
}

# The local IP of the interface attached to the 
# admin network 
variable "bastion_admin_itf_ip" {
  type = string
}

# Bastion NIC configurations
#
# This should be a list attributes of all the 
# NICs to be configured on the Bastion. The 
# list should be a list of:
#
# - private_ip
# - netmask
# - cidr
# - gateway
#
# The first network is assumed to be the DMZ
# network with the ability to NAT to the public
# domain. The second network if present is
# assumed to be the administration network.
variable "bastion_nic_config" {
  type = list(any)
}

#
# Bastion persistent volumes
#
variable "data_volume_name" {
  default = ""
}

#
# External shared folder. This is used to pass
# in the auto mount name of an external folder 
# such as a folder within the host where the 
# bastion vm is launched.
#
variable "shared_external_folder" {
  default = ""
}

#
# Bastion access configuration
#
variable "bastion_admin_api_port" {
  type = string
}

variable "bastion_admin_ssh_port" {
  type = string
}

variable "bastion_admin_user" {
  type = string
}

#
# Bastion inception instance Open VPN configuration
#
variable "vpn_type" {
  # one of "openvpn" or "ipsec"
  default = ""
}

variable "vpn_network" {
  type = string
}

variable "vpn_restricted_network" {
  type = string
}

variable "vpn_tunnel_all_traffic" {
  type = string
}

variable "vpn_idle_action" {
  type = string
}

variable "vpn_idle_shutdown_time" {
  default = 10
}

variable "vpn_users" {
  type = string
}

#
# Optional upstream VPN gateway (site-to-site IPSec).
# Peer-specific settings are managed via manage_vpn_gateway_peer at runtime.
#
variable "vpn_gateway_enabled" {
  default = false
}

variable "vpn_gateway_protocol" {
  default = "ipsec"
}

variable "vpn_gateway_nat" {
  type        = bool
  default     = false
  description = "When true, peer traffic SNATs to the bastion admin IP unless a peer YAML overrides nat. Independent of bastion_as_nat."
}

#
# Optional VPN gateway peer export for remote sites (manage_vpn_gateway_peer).
# When vpn_gateway_peer_export_path is set, writes this bastion's peer details
# (FQDN, admin CIDR, root CA) for a remote site to complete and apply.
#
variable "vpn_gateway_peer_export_path" {
  type        = string
  default     = ""
  description = "Filesystem path for this bastion's VPN gateway peer export YAML. When empty, no file is written."
}

variable "bastion_admin_subnet_cidr" {
  type        = string
  default     = ""
  description = "Admin subnet CIDR of this bastion; required when vpn_gateway_peer_export_path is set."
}

variable "vpn_gateway_peer_config_paths" {
  type        = list(string)
  default     = []
  description = "Local filesystem paths to VPN gateway peer YAML files uploaded to /usr/local/etc/vpn-gw-peers/ via cloud-init for first-boot install by configure_vpn_gateway."
}

#
# OpenVPN configuration
#
variable "ovpn_service_port" {
  type = string
}

variable "ovpn_protocol" {
  type = string
}

#
# Wireguard configuration
#
variable "wireguard_service_port" {
  type = string
}

variable "wireguard_subnet_ip" {
  type = string
}

#
# UDP port of mycs-node DERP STUN service
#
variable "derp_stun_port" {
  type = string
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

#
# Bastion inception instance SMTP configuration
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
# Bastion inception instance Squid Proxy configuration
#
variable "squidproxy_server_port" {
  type = string
}

#
# Compress cloud-init data
#
variable "compress_cloudinit" {
  default = true
}
