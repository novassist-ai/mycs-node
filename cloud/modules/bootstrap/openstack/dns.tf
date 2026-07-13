#
# External DNS for OpenStack/OVH (AWS Route53 only from this module).
#
# Google Cloud DNS and Azure DNS modules live under modules/dns/google and
# modules/dns/azure; wire them from the root module when needed.
#

module "dns" {
  count  = var.attach_dns_zone && var.dns_provider == "aws" ? 1 : 0
  source = "../../../modules/dns/aws"

  vpc_name     = var.vpc_name
  vpc_dns_zone = var.vpc_dns_zone

  bastion_public_ip    = openstack_networking_floatingip_v2.bastion_public.address
  bastion_admin_itf_ip = local.bastion_admin_itf_ip

  bastion_host_name        = var.bastion_host_name
  bastion_allow_public_ssh = var.bastion_allow_public_ssh
  smtp_relay_host          = var.smtp_relay_host

  parent_dns_zone_name = var.dns_parent_zone_name
}

locals {
  dns_vpc_dns_public_zone_id = length(module.dns) > 0 ? module.dns[0].vpc_dns_public_zone_id : ""

  dns_vpc_dns_public_zone_name = length(module.dns) > 0 ? module.dns[0].vpc_dns_public_zone_name : (
    var.attach_dns_zone ? var.vpc_dns_zone : ""
  )
}
