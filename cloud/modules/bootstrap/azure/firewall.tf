
#
# Firewall rules for communication within resources in Engineering network
#

resource "azurerm_network_security_group" "admin" {
  name = "${var.vpc_name}-admin-allow-all"
  
  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name
}

resource "azurerm_network_security_rule" "admin-allow-all" {
  name = "${var.vpc_name}-admin-allow-all"

  network_security_group_name = azurerm_network_security_group.admin.name
  resource_group_name         = azurerm_resource_group.bootstrap.name

  access    = "Allow"
  protocol  = "*"
  priority  = "500"
  direction = "Inbound"
  
  source_port_range     = "*"
  source_address_prefix = local.admin_network_cidr_range

  destination_port_range     = "*"
  destination_address_prefix = local.admin_network_cidr_range
}
