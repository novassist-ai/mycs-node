#
# Hosted zone for VPC
#

locals {
  dns_name_components = split(".", var.vpc_dns_zone)
  parent_dns_name     = join(".", slice(local.dns_name_components, 1, length(local.dns_name_components)))
  vpc_dns_hostname     = element((local.dns_name_components), 0)
}

data "azurerm_dns_zone" "parent" {
  count = var.attach_dns_zone ? 1 : 0

  name                = local.parent_dns_name
  resource_group_name = data.azurerm_resource_group.source.name
}

#
# Add Public DNS zone's nameservers to the parent zone
#
resource "azurerm_dns_ns_record" "vpc" {
  count = var.attach_dns_zone ? 1 : 0

  name         = local.vpc_dns_hostname
  zone_name    = data.azurerm_dns_zone.parent.0.name

  resource_group_name = data.azurerm_resource_group.source.name

  ttl  = 300

  records = [
    element(tolist(azurerm_dns_zone.vpc-public.0.name_servers), 0),
    element(tolist(azurerm_dns_zone.vpc-public.0.name_servers), 1),
    element(tolist(azurerm_dns_zone.vpc-public.0.name_servers), 2),
    element(tolist(azurerm_dns_zone.vpc-public.0.name_servers), 3)
  ]
}

#
# Public Zone
#
resource "azurerm_dns_zone" "vpc-public" {
  count = var.attach_dns_zone ? 1 : 0
  
  name                = var.vpc_dns_zone
  resource_group_name = azurerm_resource_group.bootstrap.name
}

#
# VPC Bastion instance DNS
#

resource "azurerm_dns_a_record" "vpc-public" {
  count = var.attach_dns_zone ? 1 : 0

  name      = local.vpc_dns_hostname
  zone_name = data.azurerm_dns_zone.parent.0.name

  resource_group_name = data.azurerm_resource_group.source.name

  ttl     = "300"
  records = [azurerm_linux_virtual_machine.bastion.public_ip_address]
}

resource "azurerm_dns_a_record" "vpc-admin" {
  count = var.attach_dns_zone && length(var.bastion_host_name) > 0 && !var.bastion_allow_public_ssh ? 1 : 0

  name = var.bastion_host_name
  zone_name = azurerm_dns_zone.vpc-public.0.name

  resource_group_name = azurerm_resource_group.bootstrap.name

  ttl     = "300"
  records = [local.bastion_admin_itf_ip]
}

resource "azurerm_dns_a_record" "vpc-mail" {
  count = var.attach_dns_zone && length(var.smtp_relay_host) > 0 ? 1 : 0

  name      = "mail.${var.vpc_dns_zone}"
  zone_name = azurerm_dns_zone.vpc-public.0.name

  resource_group_name = azurerm_resource_group.bootstrap.name

  ttl     = "300"
  records = [local.bastion_admin_itf_ip]
}

resource "azurerm_dns_mx_record" "vpc-mx" {
  count = var.attach_dns_zone && length(var.smtp_relay_host) > 0 ? 1 : 0

  name      = var.vpc_dns_zone
  zone_name = azurerm_dns_zone.vpc-public.0.name

  resource_group_name = azurerm_resource_group.bootstrap.name

  ttl = "300"

  record {
    preference = 1
    exchange   = var.vpc_dns_zone
  }
}

resource "azurerm_dns_txt_record" "vpc-txt" {
  count = var.attach_dns_zone && length(var.smtp_relay_host) > 0 ? 1 : 0

  name      = var.vpc_dns_zone
  zone_name = azurerm_dns_zone.vpc-public.0.name

  resource_group_name = azurerm_resource_group.bootstrap.name

  ttl = "300"

  record {
    value = "v=spf1 mx -all"
  }
}
