# AWS region from environment
data "aws_region" "default" {
}

locals {
  vpc_cidr         = var.regional_vpc_cidr[data.aws_region.default.region]["vpc_cidr"]
  vpc_subnet_index = element(regex("\\d{1,3}\\.(\\d{1,3})\\.\\d{1,3}\\.\\d{1,3}\\/\\d+", local.vpc_cidr), 0)
  aws_vpc_dns_zone = "test-${data.aws_region.default.region}.aws.appbricks.io"
}

#
# Bootstrap a base environment named "inceptor"
#
module "bootstrap" {
  source = "../../../modules/bootstrap/aws"

  mycs_node_private_key = var.mycs_node_private_key
  mycs_node_id_key      = var.mycs_node_id_key

  #
  # Company information used in certificate creation
  #
  company_name = "appbricks"

  organization_name = "appbricks dev"

  locality = "Boston"

  province = "MA"

  country = "US"

  #
  # VPC details
  #
  region = data.aws_region.default.region

  vpc_name = "inceptor-${data.aws_region.default.region}"
  vpc_cidr = local.vpc_cidr

  configure_admin_network = var.configure_admin_network

  # DNS Name for VPC will be 'test-<region>.aws.appbricks.io'
  vpc_dns_zone    = local.aws_vpc_dns_zone
  attach_dns_zone = var.attach_dns_zone

  # Local DNS zone. This could also be the same as the public
  # which will enable setting up a split DNS of the public zone
  # for names to map to external and internal addresses.
  vpc_internal_dns_zones = ["test-${data.aws_region.default.region}.local"]

  # Address space for all VPC regions
  global_internal_cidr = "172.16.0.0/12"

  # VPN
  vpn_idle_action = "shutdown"

  vpn_idle_shutdown_time = 720 # 12 hours

  vpn_users = [
    "user1|P@ssw0rd1",
    "user2|P@ssw0rd2"
  ]

  vpn_type = "ipsec"

  # vpn_type          = "openvpn"
  # ovpn_service_port = "2295"
  # ovpn_protocol     = "udp"

  # vpn_type               = "wireguard"
  # wireguard_service_port = "3399"

  # wireguard mesh of cloud space peers
  wireguard_mesh_node = local.vpc_subnet_index

  # Tunnel for VPN to handle situations where 
  # OpenVPN is blocked or throttled by ISP
  # tunnel_vpn_port_start = "2296"
  # tunnel_vpn_port_end   = "3396"

  vpn_tunnel_all_traffic = "yes"

  # Site-to-site IPsec gateway to OpenStack inceptor (AWS us-east-1 -> OVH UK1)
  vpn_gateway_enabled    = true
  vpn_gateway_peer_cidrs = ["172.20.64.128/26"]

  vpn_gateway_peer_export_path = "${path.module}/.${data.aws_region.default.region}/aws-${data.aws_region.default.region}-peer.yml"

  # Whether to allow SSH access to bastion server
  bastion_allow_public_ssh = true

  bastion_host_name = "inceptor"
  bastion_use_fqdn  = var.attach_dns_zone

  bastion_instance_type = "t4g.small"

  bastion_image_name  = var.bastion_image_name
  bastion_image_owner = var.bastion_image_owner

  # Issue certificates from letsencrypt.org
  certify_bastion = false

  # ICMP needs to be allowed to enable ICMP tunneling
  allow_bastion_icmp = true

  # If the SMTP relay settings are provided then
  # and SMTP server will be setup which will send
  # notifications when builds fail
  smtp_relay_host = var.smtp_relay_host

  smtp_relay_port    = var.smtp_relay_port
  smtp_relay_api_key = var.smtp_relay_api_key
}

#
# SSH Keys
#

resource "local_file" "bastion-ssh-key" {
  content  = module.bootstrap.bastion_admin_sshkey
  filename = "${path.module}/.${data.aws_region.default.region}/bastion-admin-ssh-key.pem"

  provisioner "local-exec" {
    command = "chmod 0600 ${path.module}/.${data.aws_region.default.region}/bastion-admin-ssh-key.pem"
  }
}

resource "local_file" "default-ssh-key" {
  content  = module.bootstrap.default_openssh_private_key
  filename = "${path.module}/.${data.aws_region.default.region}/default-ssh-key.pem"

  provisioner "local-exec" {
    command = "chmod 0600 ${path.module}/.${data.aws_region.default.region}/default-ssh-key.pem"
  }
}

#
# Root CA
#

resource "local_file" "root-ca-cert" {
  content  = module.bootstrap.root_ca_cert
  filename = "${path.module}/.${data.aws_region.default.region}/root-ca.pem"
}

#
# Backend state
#
terraform {
  backend "s3" {
    key = "test/cloud-inceptor"
  }
}
