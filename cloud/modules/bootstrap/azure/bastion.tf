#
# Inception Bastion instance
#

resource "azurerm_linux_virtual_machine" "bastion" {
  name          = "${var.vpc_name}-${element(split(".", var.vpc_dns_zone), 0)}"
  computer_name = element(split(".", var.vpc_dns_zone), 0)

  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name

  size = var.bastion_instance_type

  network_interface_ids = (var.configure_admin_network 
    ? [
      azurerm_network_interface.bastion-dmz.id,
      azurerm_network_interface.bastion-admin.0.id
    ]
    : [
      azurerm_network_interface.bastion-dmz.id,
    ]
  )

  source_image_id = var.bastion_use_managed_image ? data.azurerm_image.bastion.0.id : azurerm_image.bastion.0.id
  os_disk {
    name                 = "${var.vpc_name}-bastion-root"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.bastion_root_disk_size
  }

  admin_username = var.bastion_admin_user
  admin_ssh_key {
    username   = var.bastion_admin_user
    public_key = module.config.bastion_openssh_public_key
  }

  custom_data = module.config.bastion_cloud_init_config
}

#
# Attached disk for saving persistant data. This disk needs to be
# large enough for any installation packages concourse downloads.
#

resource "azurerm_managed_disk" "bastion-data" {
  name = "${var.vpc_name}-bastion-data"

  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name

  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.bastion_data_disk_size
}

resource "azurerm_virtual_machine_data_disk_attachment" "bastion-data" {
  managed_disk_id    = azurerm_managed_disk.bastion-data.id
  virtual_machine_id = azurerm_linux_virtual_machine.bastion.id

  lun     = "10"
  caching = "ReadWrite"
}

#
# Image
#

# Lookup managed image in source resource group
data "azurerm_image" "bastion" {
  count = var.bastion_use_managed_image ? 1 : 0

  name                = "${var.bastion_image_name}_${var.region}"
  resource_group_name = data.azurerm_resource_group.source.name
}

# Create image from given unmanaged disk image blob uri
resource "azurerm_image" "bastion" {
  count = var.bastion_use_managed_image ? 0 : 1

  name                = "${var.bastion_image_name}_${var.region}"
  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name

  os_disk {
    os_type      = "Linux"
    os_state     = "Generalized"
    storage_type = "Standard_LRS"
    blob_uri     = azurerm_storage_blob.bastion-image-vhd.0.url
  }

  lifecycle {
    ignore_changes = [os_disk]
  }  
}

resource "azurerm_storage_blob" "bastion-image-vhd" {
  count = var.bastion_use_managed_image ? 0 : 1

  name = "${var.bastion_image_name}.vhd"

  storage_account_name   = azurerm_storage_account.bootstrap-storage-account.name
  storage_container_name = azurerm_storage_container.bastion-image-storage-container.0.name

  type       = "Block"
  source_uri = "https://${var.bastion_image_storage_account_prefix}${local.storage_region}.blob.core.windows.net/${var.bastion_image_container}/${var.bastion_image_name}.vhd"

  lifecycle {
    ignore_changes = [type]
  }
}

resource "azurerm_storage_container" "bastion-image-storage-container" {
  count = var.bastion_use_managed_image ? 0 : 1

  name = "images"

  storage_account_id    = azurerm_storage_account.bootstrap-storage-account.id
  container_access_type = "private"
}

#
# Networking
#

locals {
  bastion_dmz_itf_ip = cidrhost(azurerm_subnet.dmz.address_prefixes[0], -3)
  bastion_admin_itf_ip = (
    var.configure_admin_network
      ? cidrhost(local.admin_network_cidr_range, -3)
      : local.bastion_dmz_itf_ip
  )
}

resource "random_uuid" "bastion-public-dns-label" {}

resource "azurerm_public_ip" "bastion-public" {
  name = "${var.vpc_name}-bastion-public"

  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name

  allocation_method = var.configure_admin_network ? "Static" : "Dynamic"

  domain_name_label = "s${replace(random_uuid.bastion-public-dns-label.result, "-", "")}"
}

resource "azurerm_network_interface" "bastion-dmz" {
  name = "${var.vpc_name}-bastion-dmz"

  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name

  ip_configuration {
    name                          = "dmz"
    subnet_id                     = azurerm_subnet.dmz.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.bastion_dmz_itf_ip

    public_ip_address_id = azurerm_public_ip.bastion-public.id
  }
}

resource "azurerm_network_interface_security_group_association" "bastion-dmz" {
  network_interface_id      = azurerm_network_interface.bastion-dmz.id
  network_security_group_id = azurerm_network_security_group.bastion-dmz.id
}

resource "azurerm_network_interface" "bastion-admin" {
  count = var.configure_admin_network ? 1 : 0

  name = "${var.vpc_name}-bastion-admin"
  
  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name

  ip_configuration {
    name                          = "dmz"
    subnet_id                     = local.admin_network_id
    private_ip_address_allocation = "Static"
    private_ip_address            =  local.bastion_admin_itf_ip
  }
}

resource "azurerm_network_interface_security_group_association" "bastion-admin" {
  count = var.configure_admin_network ? 1 : 0

  network_interface_id      = azurerm_network_interface.bastion-admin.0.id
  network_security_group_id = azurerm_network_security_group.bastion-admin.id
}

#
# Security (Firewall rules for the inception bastion instance)
#

resource "azurerm_network_security_group" "bastion-dmz" {
  name = "${var.vpc_name}-bastion-dmz"
  
  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name
}

resource "azurerm_network_security_group" "bastion-admin" {
  name = "${var.vpc_name}-bastion-admin"
  
  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name
}

resource "azurerm_network_security_rule" "bastion-http" {
  name = "${var.vpc_name}-bastion-http"

  network_security_group_name = azurerm_network_security_group.bastion-dmz.name
  resource_group_name         = azurerm_resource_group.bootstrap.name

  access    = "Allow"
  protocol  = "Tcp"
  priority  = "500"
  direction = "Inbound"
  
  source_port_range     = "*"
  source_address_prefix = "0.0.0.0/0"

  destination_port_ranges    = ["80", "443"]
  destination_address_prefix = local.bastion_dmz_itf_ip
}

resource "azurerm_network_security_rule" "bastion-ssh" {
  count = var.bastion_allow_public_ssh ? 1 : 0 

  name = "${var.vpc_name}-bastion-ssh"

  network_security_group_name = azurerm_network_security_group.bastion-dmz.name
  resource_group_name         = azurerm_resource_group.bootstrap.name

  access    = "Allow"
  protocol  = "Tcp"
  priority  = "501"
  direction = "Inbound"
  
  source_port_range     = "*"
  source_address_prefix = "0.0.0.0/0"

  destination_port_range     = var.bastion_admin_ssh_port
  destination_address_prefix = local.bastion_dmz_itf_ip
}

resource "azurerm_network_security_rule" "bastion-wireguard" {
  count = var.vpn_type == "wireguard" && length(var.wireguard_service_port) > 0 ? 1 : 0

  name = "${var.vpc_name}-bastion-wireguard"

  network_security_group_name = azurerm_network_security_group.bastion-dmz.name
  resource_group_name         = azurerm_resource_group.bootstrap.name

  access    = "Allow"
  protocol  = "Udp"
  priority  = "502"
  direction = "Inbound"
  
  source_port_range     = "*"
  source_address_prefix = "0.0.0.0/0"

  destination_port_range     = var.wireguard_service_port
  destination_address_prefix = local.bastion_dmz_itf_ip
}

resource "azurerm_network_security_rule" "bastion-openvpn" {
  count = var.vpn_type == "openvpn" && length(var.ovpn_service_port) > 0 ? 1 : 0 

  name = "${var.vpc_name}-bastion-openvpn"

  network_security_group_name = azurerm_network_security_group.bastion-dmz.name
  resource_group_name         = azurerm_resource_group.bootstrap.name

  access    = "Allow"
  protocol  = var.ovpn_protocol
  priority  = "503"
  direction = "Inbound"
  
  source_port_range     = "*"
  source_address_prefix = "0.0.0.0/0"

  destination_port_range     = var.ovpn_service_port
  destination_address_prefix = local.bastion_dmz_itf_ip
}

resource "azurerm_network_security_rule" "bastion-ipsecvpn" {
  count = var.vpn_type == "ipsec" ? 1 : 0 

  name = "${var.vpc_name}-bastion-ipsecvpn"

  network_security_group_name = azurerm_network_security_group.bastion-dmz.name
  resource_group_name         = azurerm_resource_group.bootstrap.name

  access    = "Allow"
  protocol  = "Udp"
  priority  = "504"
  direction = "Inbound"
  
  source_port_range     = "*"
  source_address_prefix = "0.0.0.0/0"

  destination_port_ranges    = ["500", "4500"]
  destination_address_prefix = local.bastion_dmz_itf_ip
}

resource "azurerm_network_security_rule" "bastion-vpntunnel" {
  count = length(var.tunnel_vpn_port_start) > 0 && length(var.tunnel_vpn_port_end) > 0 ? 1 : 0 

  name = "${var.vpc_name}-bastion-vpntunnel"

  network_security_group_name = azurerm_network_security_group.bastion-dmz.name
  resource_group_name         = azurerm_resource_group.bootstrap.name

  access    = "Allow"
  protocol  = "*"
  priority  = "505"
  direction = "Inbound"
  
  source_port_range     = "*"
  source_address_prefix = "0.0.0.0/0"

  destination_port_range     = "${var.tunnel_vpn_port_start}-${var.tunnel_vpn_port_end}"
  destination_address_prefix = local.bastion_dmz_itf_ip
}

resource "azurerm_network_security_rule" "bastion-derp-stun" {
  count = length(var.derp_stun_port) > 0 == 0 ? 0 : 1

  name = "${var.vpc_name}-bastion-derp-stun"

  network_security_group_name = azurerm_network_security_group.bastion-dmz.name
  resource_group_name         = azurerm_resource_group.bootstrap.name

  access    = "Allow"
  protocol  = "Udp"
  priority  = "506"
  direction = "Inbound"

  source_port_range     = "*"
  source_address_prefix = "0.0.0.0/0"

  destination_port_range     = var.derp_stun_port
  destination_address_prefix = local.bastion_dmz_itf_ip
}

resource "azurerm_network_security_rule" "bastion-smtp-ext" {
  count = length(var.smtp_relay_host) == 0 ? 0 : 1 

  name = "${var.vpc_name}-bastion-smtp-ext"

  network_security_group_name = azurerm_network_security_group.bastion-dmz.name
  resource_group_name         = azurerm_resource_group.bootstrap.name

  access    = "Allow"
  protocol  = "Tcp"
  priority  = "507"
  direction = "Inbound"

  source_port_range     = "*"
  source_address_prefix = "0.0.0.0/0"

  destination_port_range     = "25"
  destination_address_prefix = local.bastion_dmz_itf_ip
}

resource "azurerm_network_security_rule" "bastion-deny-dmz" {
  name = "${var.vpc_name}-bastion-deny-dmz"

  network_security_group_name = azurerm_network_security_group.bastion-dmz.name
  resource_group_name         = azurerm_resource_group.bootstrap.name

  access    = "Deny"
  protocol  = "*"
  priority  = "600"
  direction = "Inbound"

  source_port_range     = "*"
  source_address_prefix = azurerm_subnet.dmz.address_prefixes[0]

  destination_port_range     = "*"
  destination_address_prefix = local.bastion_dmz_itf_ip
}

resource "azurerm_network_security_rule" "bastion-smtp-int" {
  count = length(var.smtp_relay_host) == 0 ? 0 : 1 

  name = "${var.vpc_name}-bastion-smtp-int"

  network_security_group_name = azurerm_network_security_group.bastion-admin.name
  resource_group_name         = azurerm_resource_group.bootstrap.name

  access    = "Allow"
  protocol  = "Tcp"
  priority  = "500"
  direction = "Inbound"

  source_port_range       = "*"
  source_address_prefixes = [var.vpn_network, var.vpc_cidr]

  destination_port_range     = "2525"
  destination_address_prefix = local.bastion_admin_itf_ip
}

resource "azurerm_network_security_rule" "bastion-proxy" {
  count = length(var.squidproxy_server_port) == 0 ? 0 : 1 

  name = "${var.vpc_name}-bastion-proxy"

  network_security_group_name = azurerm_network_security_group.bastion-admin.name
  resource_group_name         = azurerm_resource_group.bootstrap.name

  access    = "Allow"
  protocol  = "Tcp"
  priority  = "501"
  direction = "Inbound"

  source_port_range       = "*"
  source_address_prefixes = [var.vpn_network, var.vpc_cidr]

  destination_port_range     = var.squidproxy_server_port
  destination_address_prefix = local.bastion_admin_itf_ip
}

resource "azurerm_network_security_rule" "bastion-deny-vpc" {
  name = "${var.vpc_name}-bastion-deny-vpc"

  network_security_group_name = azurerm_network_security_group.bastion-admin.name
  resource_group_name         = azurerm_resource_group.bootstrap.name

  access    = "Deny"
  protocol  = "*"
  priority  = "600"
  direction = "Inbound"

  source_port_range     = "*"
  source_address_prefix = var.vpc_cidr

  destination_port_range     = "*"
  destination_address_prefix = local.bastion_admin_itf_ip
}
