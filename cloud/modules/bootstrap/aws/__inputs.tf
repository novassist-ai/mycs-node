#
# AWS compute region
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
  // Used to calculate subnet CIDR 
  // if not explicitly provided
  default = 4
}

variable "vpc_subnet_start" {
  // Used to calculate subnet CIDR 
  // if not explicitly provided
  default = 1
}

variable "vpc_internal_dns_zones" {
  default = [""]
}

variable "vpc_internal_dns_records" {
  default = []
}

variable "dmz_cidr" {
  // DMZ Subnet CIDR for each AZ
  default = []
}

variable "admin_cidr" {
  // Amin Subnet CIDR for each AZ
  default = []
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
  default = "t4g.nano"
}

variable "bastion_image_name" {
  default = "mycs-node-image_dev"
}

variable "bastion_image_owner" {
  default = "self"
}

variable "bastion_root_disk_type" {
  default = "standard"
}

variable "bastion_root_disk_size" {
  default = 8
}

variable "bastion_data_disk_type" {
  default = "standard"
}

variable "bastion_data_disk_size" {
  default = 5
}

variable "bastion_data_disk_device_name" {
  # The device name specified in the
  # aws_volume_attachment does not appear
  # to take effect. This variable explicitly
  # names the device name AWS assigns to
  # the attached disk so the mount_volume
  # script can find it.
  default = "nvme1n1"
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

#
# Setup Bastion as the NAT
#
variable "bastion_as_nat" {
  default = true
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
  default = ""
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
# Optional upstream VPN gateway (site-to-site IPsec).
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
  description = "Default SNAT behaviour for VPN gateway peers on this bastion (overridable per peer YAML)."
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

variable "jumpbox_ami_name" {
  default = "ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-arm64-server-*"
}

variable "jumpbox_ami_arch" {
  default = "arm64"
}

variable "jumpbox_ami_owner" {
  default = "099720109477" # Canonical
}

variable "jumpbox_instance_type" {
  default = "t4g.nano"
}

variable "jumpbox_data_disk_size" {
  default = "160"
}

variable "jumpbox_data_disk_device_name" {
  # The device name specified in the
  # aws_volume_attachment does not appear
  # to take effect. This variable explicitly
  # names the device name AWS assigns to
  # the attached disk so the mount_volume
  # script can find it.
  default = "nvme1n1"
}