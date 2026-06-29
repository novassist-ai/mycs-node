#
# Bootstrap a base environment named "inceptor" on OVHcloud Public Cloud (OpenStack)
#

locals {
  openstack_vpc_dns_zone = "test-${lower(var.region)}.ovh.appbricks.io"
  aws_peer = {
    region       = "us-east-1"
    vpc_cidr     = "172.20.8.0/22"
    bastion_fqdn = "test-us-east-1.aws.appbricks.io"
    root_ca_file = "${path.module}/../aws/.us-east-1/root-ca.pem"
  }
}

module "bootstrap" {
  source = "../../../modules/bootstrap/openstack"

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
  region = var.region

  external_network_name = var.external_network_name

  vpc_name = "inceptor-${var.region}"
  vpc_cidr = var.regional_vpc_cidr[var.region]["vpc_cidr"]

  configure_admin_network = var.configure_admin_network

  # Public DNS: delegated child zone in AWS Route53 (parent: ovh.appbricks.io)
  vpc_dns_zone    = local.openstack_vpc_dns_zone
  attach_dns_zone = var.attach_dns_zone
  dns_provider    = "aws"

  dns_parent_zone_name = var.dns_parent_zone_name

  # Local DNS zone served by PowerDNS on the bastion
  vpc_internal_dns_zones = ["test-${lower(var.region)}.local"]

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

  vpn_tunnel_all_traffic = "yes"

  # Site-to-site IPsec gateway to AWS inceptor (UK1 -> us-east-1)
  vpn_gateway_enabled    = true
  vpn_gateway_peer_cidrs = ["172.20.9.192/26"]

  bastion_allow_public_ssh = true

  bastion_host_name = "inceptor"
  bastion_use_fqdn  = var.attach_dns_zone

  bastion_image_name_regex = var.bastion_image_name_regex
  bastion_flavor           = var.bastion_flavor

  bastion_dns = var.bastion_dns

  certify_bastion = false

  allow_bastion_icmp = true

  smtp_relay_host    = var.smtp_relay_host
  smtp_relay_port    = var.smtp_relay_port
  smtp_relay_api_key = var.smtp_relay_api_key
}

#
# SSH Keys
#

resource "local_file" "bastion-ssh-key" {
  content  = module.bootstrap.bastion_admin_sshkey
  filename = "${path.module}/.${var.region}/bastion-admin-ssh-key.pem"

  provisioner "local-exec" {
    command = "chmod 0600 ${path.module}/.${var.region}/bastion-admin-ssh-key.pem"
  }
}

resource "local_file" "default-ssh-key" {
  content  = module.bootstrap.default_openssh_private_key
  filename = "${path.module}/.${var.region}/default-ssh-key.pem"

  provisioner "local-exec" {
    command = "chmod 0600 ${path.module}/.${var.region}/default-ssh-key.pem"
  }
}

#
# Root CA
#

resource "local_file" "root-ca-cert" {
  content  = module.bootstrap.root_ca_cert
  filename = "${path.module}/.${var.region}/root-ca.pem"
}

#
# Providers
#

provider "openstack" {
  region       = var.region
  max_retries  = 10
}

# Route53 API region (parent zone ovh.appbricks.io lives in AWS)
provider "aws" {
  region = var.aws_dns_region
}

terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.1.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}
