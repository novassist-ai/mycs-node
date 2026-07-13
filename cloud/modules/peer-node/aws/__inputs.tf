#
# Ingress VPC and Region
#
variable "ingress_vpc_name" {
  type = string
}
variable "ingress_vpc_id" {
  type = string
}
variable "ingress_region" {
  type = string
}
variable "ingress_bastion_id" {
  type = string
}
variable "ingress_bastion_host" {
  type = string
}
variable "ingress_bastion_sshkey" {
  type = string
}
variable "ingress_bastion_admin" {
  type = string
}
variable "ingress_bastion_password" {
  type = string
}

#
# Egress VPC and Region
#
variable "egress_vpc_name" {
  type = string
}
variable "egress_vpc_id" {
  type = string
}
variable "egress_region" {
  type = string
}
variable "egress_bastion_id" {
  type = string
}
variable "egress_bastion_host" {
  type = string
}
variable "egress_bastion_sshkey" {
  type = string
}
variable "egress_bastion_admin" {
  type = string
}
variable "egress_bastion_password" {
  type = string
}
