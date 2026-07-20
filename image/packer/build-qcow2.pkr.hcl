packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
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

variable "iso_url" {
  type = string
}

variable "iso_checksum" {
  type = string
}

variable "output_directory" {
  type = string
}

variable "qemu_binary" {
  type = string
}

variable "accelerator" {
  type = string
}

variable "machine_type" {
  type = string
}

variable "cpu_model" {
  type    = string
  default = "host"
}

variable "efi_boot" {
  type    = bool
  default = false
}

variable "efi_firmware_code" {
  type    = string
  default = ""
}

variable "efi_firmware_vars" {
  type    = string
  default = ""
}

variable "ssh_private_key_file" {
  type = string
}

variable "seed_dir" {
  type        = string
  description = "Directory containing NoCloud user-data and meta-data"
}

variable "memory" {
  type    = number
  default = 8192
}

variable "cpus" {
  type    = number
  default = 4
}

variable "disk_size" {
  type    = string
  default = "25600M"
}

variable "headless" {
  type    = bool
  default = true
}

variable "use_default_display" {
  type    = bool
  default = false
}

variable "boot_wait" {
  type    = string
  default = "30s"
}

source "qemu" "bastion" {
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum
  disk_image   = true

  output_directory = var.output_directory
  vm_name          = var.image_name
  format           = "qcow2"

  qemu_binary    = var.qemu_binary
  accelerator    = var.accelerator
  machine_type   = var.machine_type
  cpu_model      = var.cpu_model
  memory         = var.memory
  cpus           = var.cpus
  disk_size      = var.disk_size
  disk_interface = "virtio"
  net_device     = "virtio-net"

  efi_boot          = var.efi_boot
  efi_firmware_code = var.efi_firmware_code == "" ? null : var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars == "" ? null : var.efi_firmware_vars

  headless            = var.headless
  use_default_display = var.use_default_display
  boot_wait           = var.boot_wait

  ssh_username           = "ubuntu"
  ssh_private_key_file   = var.ssh_private_key_file
  ssh_timeout            = "45m"
  ssh_handshake_attempts = 100

  # Do NOT set qemuargs — it replaces Packer's disk/network/EFI args and leaves
  # the VM with only the seed CD (SSH never comes up).
  # Prefer Packer cd_files; with xorriso on PATH this is ISO9660 NoCloud-compatible
  # (avoids macOS hdiutil HFS hybrids that cloud-init ignores).
  cd_files = [
    "${var.seed_dir}/user-data",
    "${var.seed_dir}/meta-data",
  ]
  cd_label = "cidata"

  shutdown_command = "sudo /sbin/shutdown -hP now"
  shutdown_timeout = "5m"
}

build {
  name = "qcow2-bastion"
  sources = [
    "source.qemu.bastion"
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
