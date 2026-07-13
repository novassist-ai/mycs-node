#
# Virtual Networks#

locals {
  admin_network_id = (var.configure_admin_network
    ? azurerm_subnet.admin.0.id
    : azurerm_subnet.dmz.id
  )
  admin_network_cidr_range = (var.configure_admin_network
    ? azurerm_subnet.admin.0.address_prefixes[0]
    : azurerm_subnet.dmz.address_prefixes[0]
  )
}

resource "azurerm_virtual_network" "vpc" {
  name                = "${var.vpc_name}-network"
  address_space       = [var.vpc_cidr]
  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name
}

resource "azurerm_subnet" "dmz" {
  name                 = "${var.vpc_name}-dmz-subnet"
  resource_group_name  = azurerm_resource_group.bootstrap.name
  virtual_network_name = azurerm_virtual_network.vpc.name

  address_prefixes = [(
    length(var.dmz_cidr) != 0 
      ? var.dmz_cidr 
      : cidrsubnet(var.vpc_cidr, var.vpc_subnet_bits, var.vpc_subnet_start)
  )]
}

resource "azurerm_subnet" "admin" {
  count = var.configure_admin_network ? 1 : 0
  
  name                 = "${var.vpc_name}-admin-subnet"
  resource_group_name  = azurerm_resource_group.bootstrap.name
  virtual_network_name = azurerm_virtual_network.vpc.name

  address_prefixes = [(
    length(var.admin_cidr) != 0 
      ? var.admin_cidr 
      : (length(var.dmz_cidr) != 0 
        ? cidrsubnet(var.vpc_cidr, var.vpc_subnet_bits, var.vpc_subnet_start) 
        : cidrsubnet(var.vpc_cidr, var.vpc_subnet_bits, var.vpc_subnet_start+1))
  )]
}

resource "azurerm_route_table" "admin" {
  count = var.configure_admin_network ? 1 : 0

  name                = "${var.vpc_name}-admin-route-table"
  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name

  route {
    name                   = "nat"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.bastion_admin_itf_ip
  }
}

resource "azurerm_subnet_route_table_association" "admin-routes" {
  count = var.configure_admin_network ? 1 : 0

  subnet_id      = azurerm_subnet.admin.0.id
  route_table_id = azurerm_route_table.admin.0.id
}
