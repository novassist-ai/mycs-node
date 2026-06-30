packer {
  required_plugins {
    vagrant = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/vagrant"
    }
  }
}

variable "name" {
  type = string
}

variable "version" {
  type = string
}

variable "base_image" {
  type = string
}

variable "build_dir" {
  type = string
}

source "vagrant" "bastion" {
  source_path   = var.base_image
  output_dir    = "${var.build_dir}/.build"
  box_name      = "${var.name}_${var.version}"
  provider      = "virtualbox"
  teardown_method = "destroy"
  communicator  = "ssh"
  add_clean     = true
  add_force     = true
}

build {
  name = "vagrant-bastion"
  sources = [
    "source.vagrant.bastion"
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
    inline_shebang   = "/bin/bash -x"
    execute_command  = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/inceptor-scripts/*",
      "/tmp/inceptor-scripts/install_packages"
    ]
  }

  post-processor "vagrant-cloud" {
    box_tag = "mycloudspace/mycs-bastion"
    version = var.version
  }
}

