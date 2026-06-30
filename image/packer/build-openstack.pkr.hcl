packer {
  required_plugins {
    openstack = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/openstack"
    }
  }
}

variable "build_dir" {
  type = string
}

variable "image_name" {
  type = string
}

variable "image_version" {
  type = string
}

variable "region" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "source_image_id" {
  type = string
}

variable "flavor_id" {
  type = string
}

variable "network_id" {
  type = string
}

source "openstack" "bastion" {
  region         = var.region
  tenant_id      = var.tenant_id
  image_name     = var.image_name
  source_image   = var.source_image_id
  flavor         = var.flavor_id
  ssh_username   = "ubuntu"
  ssh_ip_version = "4"
  ssh_timeout    = "45m"
  networks       = [var.network_id]

  image_visibility = "private"
  image_min_disk   = 25
  force_delete     = true

  metadata = {
    distribution        = "ubuntu"
    hw_disk_bus         = "scsi"
    hw_scsi_model       = "virtio-scsi"
    hw_qemu_guest_agent = "yes"
    image_original_user = "ubuntu"
    os_type             = "linux"
    os_distro           = "ubuntu"
    mycd_version        = var.image_version
  }
}

build {
  name = "openstack-bastion"
  sources = [
    "source.openstack.bastion"
  ]

  provisioner "file" {
    source      = "${var.build_dir}/.download"
    destination = "/tmp/download"
  }

  provisioner "file" {
    source      = "${var.build_dir}/scripts/config"
    destination = "/tmp/inceptor-scripts"
  }

  provisioner "file" {
    source      = "${var.build_dir}/www"
    destination = "/tmp/www-static-home"
  }

  provisioner "shell" {
    expect_disconnect = true
    inline_shebang    = "/bin/bash -x"
    execute_command   = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/inceptor-scripts/*",
      "/tmp/inceptor-scripts/install_packages"
    ]
  }
}
