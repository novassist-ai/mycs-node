#
# Jumpbox
#

locals {
  local_dns = "${length(var.vpc_internal_dns_zones) > 0 
    ? element(var.vpc_internal_dns_zones, 0) : ""}"

  jumpbox_ip = cidrhost(local.admin_network_cidr_range, 10)
  jumpbox_dns = (
    var.deploy_jumpbox && length(local.local_dns) > 0 
      ? format("jumpbox.%s", local.local_dns) 
      : ""
  )
  jumpbox_dns_record = (
    length(local.jumpbox_dns) > 0 
      ? format("%s:%s", local.jumpbox_dns, local.jumpbox_ip) 
      : ""
  )
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  count = var.deploy_jumpbox ? 1 : 0

  name          = "${var.vpc_name}-jumpbox"
  computer_name = "jumpbox"

  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name

  size                  = "Standard_B1s"
  network_interface_ids = [azurerm_network_interface.jumpbox-admin.0.id]

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  os_disk {
    name                 = "${var.vpc_name}-jumpbox-root"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = "40"
  }

  admin_username = "ubuntu"
  admin_ssh_key {
    username   = "ubuntu"
    public_key = tls_private_key.default-ssh-key.public_key_openssh
  }
  
  custom_data = data.cloudinit_config.jumpbox-cloudinit.rendered
}

data "cloudinit_config" "jumpbox-cloudinit" {
  gzip          = true
  base64_encode = true

  part {
    content = <<USER_DATA
#cloud-config

write_files:
- encoding: b64
  content: ${base64encode(templatefile(
    "${path.module}/scripts/mount-volume.sh",
    {
      attached_device_name = "sdc"
      mount_directory      = "/data"
      world_readable       = "true"
    }
  ))}
  path: /root/mount-volume.sh
  permissions: '0744'

runcmd: 

# Install Docker
- |
  rm -rf /var/lib/apt/lists/*
  echo "waiting 180 seconds for network to become available"
  timeout 180 /bin/bash -c \
    "until curl -s --fail $(cat /etc/apt/sources.list | head -1 | cut -d ' ' -f2) 2>&1 >/dev/null; do echo waiting ...; sleep 1; done"

  export DEBIAN_FRONTEND=noninteractive
  
  apt-get update
  apt-get -o Acquire::ForceIPv4=true install -y \
    pkg-config apt-transport-https ca-certificates gnupg lsb-release \
    cmake build-essential openssl libcurl4-openssl-dev libssl-dev libffi-dev libxml2 libxml2-dev \
    parted dosfstools squashfs-tools efibootmgr net-tools ipcalc \
    expect rsync curl jq zip git python3.9 python3-dev python3-pip python-is-python3
  
  distro=$(lsb_release -is | tr '[:upper:]' '[:lower:]')

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$distro/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/$distro \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  rm -fr awscliv2.zip aws

# Mount data volume
- /root/mount-volume.sh

USER_DATA
  }
}

resource "azurerm_network_interface" "jumpbox-admin" {
  count = var.deploy_jumpbox ? 1 : 0

  name = "${var.vpc_name}-jumpbox-admin"
  
  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name

  ip_configuration {
    name                          = "admin"
    subnet_id                     = local.admin_network_id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.jumpbox_ip
  }
}

resource "azurerm_network_interface_security_group_association" "jumpbox-admin" {
  count = var.deploy_jumpbox ? 1 : 0

  network_interface_id      = azurerm_network_interface.jumpbox-admin.0.id
  network_security_group_id = azurerm_network_security_group.admin.id
}

#
# Jumpbox data volume
#

resource "azurerm_managed_disk" "jumpbox-data" {
  count = var.deploy_jumpbox ? 1 : 0

  name = "${var.vpc_name}-jumpbox-data"

  location            = azurerm_resource_group.bootstrap.location
  resource_group_name = azurerm_resource_group.bootstrap.name

  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.jumpbox_data_disk_size
}

resource "azurerm_virtual_machine_data_disk_attachment" "jumpbox-data" {
  count = var.deploy_jumpbox ? 1 : 0

  managed_disk_id    = azurerm_managed_disk.jumpbox-data.0.id
  virtual_machine_id = azurerm_linux_virtual_machine.jumpbox.0.id

  lun     = "10"
  caching = "ReadWrite"
}
