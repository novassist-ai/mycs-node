packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_access_key" {
  type    = string
  default = env("AWS_ACCESS_KEY_ID")
}

variable "aws_secret_key" {
  type    = string
  default = env("AWS_SECRET_ACCESS_KEY")
}

variable "region" {
  type = string
}

variable "ami" {
  type = string
}

variable "name" {
  type = string
}

variable "build_dir" {
  type = string
}

source "amazon-ebs" "bastion" {
  access_key    = var.aws_access_key
  secret_key    = var.aws_secret_key
  region        = var.region
  source_ami    = var.ami
  instance_type = "t4g.micro"
  ssh_username  = "ubuntu"
  ami_name      = var.name
}

build {
  name = "aws-bastion"
  sources = [
    "source.amazon-ebs.bastion"
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
    expect_disconnect   = true
    inline_shebang      = "/bin/bash -x"
    execute_command     = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/inceptor-scripts/*",
      "/tmp/inceptor-scripts/install_packages"
    ]
  }
}

