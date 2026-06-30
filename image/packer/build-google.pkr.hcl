packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "gcp_acct_file" {
  type    = string
  default = env("GOOGLE_CREDENTIALS")
}

variable "gcp_project_id" {
  type    = string
  default = env("GOOGLE_PROJECT")
}

variable "gcp_zone" {
  type    = string
  default = env("GOOGLE_ZONE")
}

variable "source_image_family" {
  type = string
}

variable "image_name" {
  type = string
}

variable "publish_bucket" {
  type = string
}

variable "publish_image_name" {
  type = string
}

variable "build_dir" {
  type = string
}

source "googlecompute" "bastion" {
  account_file       = var.gcp_acct_file
  project_id         = var.gcp_project_id
  zone               = var.gcp_zone
  source_image_family = var.source_image_family
  ssh_username       = "ubuntu"
  image_family       = "mycs-bastion"
  image_name         = var.image_name
  image_description  = "MyCS bastion instance base image"
  disk_size          = 10
}

build {
  name = "google-bastion"
  sources = [
    "source.googlecompute.bastion"
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

  post-processor "googlecompute-export" {
    paths              = ["gs://${var.publish_bucket}/mycs-bastion/${var.publish_image_name}.tar.gz"]
    keep_input_artifact = true
  }
}

