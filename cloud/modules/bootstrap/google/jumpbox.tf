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

  jumpbox_dns_record = (
    length(local.jumpbox_dns) > 0 
      ? format("%s:%s", local.jumpbox_dns, google_compute_address.jumpbox.0.address) 
      : ""
  )
}

resource "google_compute_instance" "jumpbox" {
  count = length(local.jumpbox_dns) > 0 ? 1 : 0

  name         = "${var.vpc_name}-jumpbox"
  machine_type = "f1-micro"
  zone         = data.google_compute_zones.available.names[0]

  allow_stopping_for_update = true

  tags = [
    "nat-${var.vpc_name}-${var.region}",
    "allow-int-ssh",
  ]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = "40"
    }
  }

  attached_disk {
    source = google_compute_disk.jumpbox-data.0.self_link
  }

  network_interface {
    subnetwork = (var.configure_admin_network
      ? google_compute_subnetwork.admin.0.self_link
      : google_compute_subnetwork.dmz.self_link
    )
    network_ip = google_compute_address.jumpbox.0.address
  }

  metadata = {
    ssh-keys = "ubuntu:${tls_private_key.default-ssh-key.public_key_openssh}"

    user-data = <<USER_DATA
#cloud-config

write_files:
- encoding: b64
  content: ${base64encode(templatefile(
    "${path.module}/scripts/mount-volume.sh",
    {
      attached_device_name = "sdb"
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

resource "google_compute_address" "jumpbox" {
  count = length(local.jumpbox_dns) > 0 ? 1 : 0
  
  name         = "${var.vpc_name}-jumpbox"
  address_type = "INTERNAL"

  subnetwork = (var.configure_admin_network
    ? google_compute_subnetwork.admin.0.self_link
    : google_compute_subnetwork.dmz.self_link
  )
  region     = var.region
}

#
# Jumpbox data volume
#

resource "google_compute_disk" "jumpbox-data" {
  count = length(local.jumpbox_dns) > 0 ? 1 : 0

  name = "${var.vpc_name}-jumpbox-data"
  type = "pd-standard"
  zone = data.google_compute_zones.available.names[0]
  size = var.jumpbox_data_disk_size
}
