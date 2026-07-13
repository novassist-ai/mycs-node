#
# Azure DNS (public DNS only)
#

data "azurerm_dns_zone" "parent" {
  name                = local.azure_parent_zone_name
  resource_group_name = var.azure_resource_group
}

resource "azurerm_dns_zone" "vpc_public" {
  name                = var.vpc_dns_zone
  resource_group_name = var.azure_resource_group
}

resource "azurerm_dns_ns_record" "vpc" {
  name                = local.vpc_dns_hostname
  zone_name           = data.azurerm_dns_zone.parent.name
  resource_group_name = var.azure_resource_group

  ttl = 300

  records = [
    element(tolist(azurerm_dns_zone.vpc_public.name_servers), 0),
    element(tolist(azurerm_dns_zone.vpc_public.name_servers), 1),
    element(tolist(azurerm_dns_zone.vpc_public.name_servers), 2),
    element(tolist(azurerm_dns_zone.vpc_public.name_servers), 3),
  ]
}

resource "azurerm_dns_a_record" "vpc_public" {
  name                = local.vpc_dns_hostname
  zone_name           = data.azurerm_dns_zone.parent.name
  resource_group_name = var.azure_resource_group

  ttl     = "300"
  records = [var.bastion_public_ip]
}

resource "azurerm_dns_a_record" "vpc_admin" {
  count = (
    length(var.bastion_host_name) > 0
    && !var.bastion_allow_public_ssh
  ) ? 1 : 0

  name                = var.bastion_host_name
  zone_name           = azurerm_dns_zone.vpc_public.name
  resource_group_name = var.azure_resource_group

  ttl     = "300"
  records = [var.bastion_admin_itf_ip]
}

resource "azurerm_dns_a_record" "vpc_mail" {
  count = length(var.smtp_relay_host) > 0 ? 1 : 0

  name                = "mail.${var.vpc_dns_zone}"
  zone_name           = azurerm_dns_zone.vpc_public.name
  resource_group_name = var.azure_resource_group

  ttl     = "300"
  records = [var.bastion_admin_itf_ip]
}

resource "azurerm_dns_mx_record" "vpc_mx" {
  count = length(var.smtp_relay_host) > 0 ? 1 : 0

  name                = var.vpc_dns_zone
  zone_name           = azurerm_dns_zone.vpc_public.name
  resource_group_name = var.azure_resource_group

  ttl = "300"

  record {
    preference = 1
    exchange   = var.vpc_dns_zone
  }
}

resource "azurerm_dns_txt_record" "vpc_txt" {
  count = length(var.smtp_relay_host) > 0 ? 1 : 0

  name                = var.vpc_dns_zone
  zone_name           = azurerm_dns_zone.vpc_public.name
  resource_group_name = var.azure_resource_group

  ttl = "300"

  record {
    value = "v=spf1 mx -all"
  }
}
