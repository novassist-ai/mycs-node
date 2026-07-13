variable "vpc_name" {
  type = string
}

variable "vpc_dns_zone" {
  type = string
}

variable "bastion_public_ip" {
  type = string
}

variable "bastion_admin_itf_ip" {
  type = string
}

variable "bastion_host_name" {
  default = ""
}

variable "bastion_allow_public_ssh" {
  default = true
}

variable "smtp_relay_host" {
  default = ""
}

variable "parent_dns_zone_name" {
  default     = ""
  description = "Parent DNS zone for NS delegation. Defaults to the parent domain of vpc_dns_zone."
}

variable "azure_resource_group" {
  type        = string
  description = "Azure resource group for parent and delegated DNS zones."
}
