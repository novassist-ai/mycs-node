#
# Jumpbox
#

locals {
  local_dns = (
    length(var.vpc_internal_dns_zones) > 0
    ? element(var.vpc_internal_dns_zones, 0)
    : ""
  )
  jumpbox_dns = (
    var.deploy_jumpbox && length(local.local_dns) > 0
    ? format("jumpbox.%s", local.local_dns)
    : ""
  )
  jumpbox_ip = (
    length(local.jumpbox_dns) > 0
    ? cidrhost(
      var.configure_admin_network
      ? openstack_networking_subnet_v2.admin[0].cidr
      : openstack_networking_subnet_v2.dmz.cidr,
      var.configure_admin_network ? 5 : 10
    )
    : ""
  )
  jumpbox_subnet_cidr = (
    var.configure_admin_network
    ? openstack_networking_subnet_v2.admin[0].cidr
    : openstack_networking_subnet_v2.dmz.cidr
  )
  jumpbox_subnet_prefix = split("/", local.jumpbox_subnet_cidr)[1]
  jumpbox_default_gateway = (
    var.configure_admin_network && var.bastion_as_nat
    ? local.bastion_admin_itf_ip
    : cidrhost(local.jumpbox_subnet_cidr, 1)
  )
  jumpbox_dns_record = (
    length(local.jumpbox_dns) > 0
    ? format("%s:%s", local.jumpbox_dns, local.jumpbox_ip)
    : ""
  )
  jumpbox_dns_server = local.bastion_admin_itf_ip
}

data "openstack_compute_flavor_v2" "jumpbox" {
  count = length(local.jumpbox_dns) > 0 ? 1 : 0

  name = var.jumpbox_flavor
}

data "openstack_images_image_v2" "jumpbox" {
  count = length(local.jumpbox_dns) > 0 ? 1 : 0

  name        = var.jumpbox_image_name
  most_recent = true
}

resource "openstack_networking_port_v2" "jumpbox" {
  count = length(local.jumpbox_dns) > 0 ? 1 : 0

  name               = "${var.vpc_name}: jumpbox"
  network_id         = var.configure_admin_network ? local.admin_network_id : openstack_networking_network_v2.dmz.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.internal.id]

  fixed_ip {
    subnet_id  = var.configure_admin_network ? openstack_networking_subnet_v2.admin[0].id : openstack_networking_subnet_v2.dmz.id
    ip_address = local.jumpbox_ip
  }
}

resource "openstack_compute_instance_v2" "jumpbox" {
  count = length(local.jumpbox_dns) > 0 ? 1 : 0

  name      = "${var.vpc_name}: jumpbox"
  flavor_id = data.openstack_compute_flavor_v2.jumpbox[0].id
  image_id  = data.openstack_images_image_v2.jumpbox[0].id
  key_pair  = openstack_compute_keypair_v2.default.name

  network {
    port = openstack_networking_port_v2.jumpbox[0].id
  }

  user_data = <<USERDATA
#cloud-config

write_files:
- path: /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
  content: |
    network: {config: disabled}
- path: /etc/netplan/99-jumpbox.yaml
  content: |
    network:
      version: 2
      ethernets:
        jumpbox0:
          dhcp4: false
          dhcp6: false
          addresses:
          - ${local.jumpbox_ip}/${local.jumpbox_subnet_prefix}
          routes:
          - to: default
            via: ${local.jumpbox_default_gateway}
          nameservers:
            addresses: [${local.jumpbox_default_gateway}]
          match:
            macaddress: ${lower(openstack_networking_port_v2.jumpbox[0].mac_address)}
          set-name: jumpbox0
- path: /etc/systemd/resolved.conf.d/bastion-dns.conf
  content: |
    [Resolve]
    MulticastDNS=no
    LLMNR=no
    DNS=${local.jumpbox_dns_server}
    Domains=~.
- encoding: b64
  content: ${base64encode(templatefile(
  "${path.module}/scripts/mount-volume.sh",
  {
    attached_device_name = var.jumpbox_data_disk_device_name
    mount_directory      = "/data"
    world_readable       = "true"
  }
))}
  path: /root/mount-volume.sh
  permissions: '0744'

runcmd:
- netplan apply
- systemctl restart systemd-resolved

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
    expect rsync curl jq zip git python3 python3-dev python3-pip python-is-python3

  distro=$(lsb_release -is | tr '[:upper:]' '[:lower:]')

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$distro/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/$distro \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Mount data volume
- /root/mount-volume.sh

USERDATA
}

resource "openstack_blockstorage_volume_v3" "jumpbox_data" {
  count = length(local.jumpbox_dns) > 0 ? 1 : 0

  name = "${var.vpc_name}: jumpbox-data"
  size = var.jumpbox_data_disk_size
}

resource "openstack_compute_volume_attach_v2" "jumpbox_data" {
  count = length(local.jumpbox_dns) > 0 ? 1 : 0

  instance_id = openstack_compute_instance_v2.jumpbox[0].id
  volume_id   = openstack_blockstorage_volume_v3.jumpbox_data[0].id
}
