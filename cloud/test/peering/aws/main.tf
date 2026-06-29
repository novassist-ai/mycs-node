#
# Peer VPN node regions
#

module "peer-node" {
  source = "../../../modules/peer-node/aws"

  ingress_vpc_name   = "${data.terraform_remote_state.ingress-peer-node.outputs.vpc_name}"
  ingress_vpc_id     = "${data.terraform_remote_state.ingress-peer-node.outputs.vpc_id}"
  ingress_region     = "${var.peer_node_ingress_region}"
  ingress_bastion_id = "${data.terraform_remote_state.ingress-peer-node.outputs.bastion_instance_id}"

  ingress_bastion_host     = "${data.terraform_remote_state.ingress-peer-node.outputs.bastion_fqdn}"
  ingress_bastion_sshkey   = "${data.terraform_remote_state.ingress-peer-node.outputs.bastion_admin_sshkey}"
  ingress_bastion_admin    = "${data.terraform_remote_state.ingress-peer-node.outputs.bastion_admin_user}"
  ingress_bastion_password = "${data.terraform_remote_state.ingress-peer-node.outputs.bastion_admin_password}"

  egress_vpc_name   = "${data.terraform_remote_state.egress-peer-node.outputs.vpc_name}"
  egress_vpc_id     = "${data.terraform_remote_state.egress-peer-node.outputs.vpc_id}"
  egress_region     = "${var.peer_node_egress_region}"
  egress_bastion_id = "${data.terraform_remote_state.egress-peer-node.outputs.bastion_instance_id}"

  egress_bastion_host     = "${data.terraform_remote_state.egress-peer-node.outputs.bastion_fqdn}"
  egress_bastion_sshkey   = "${data.terraform_remote_state.egress-peer-node.outputs.bastion_admin_sshkey}"
  egress_bastion_admin    = "${data.terraform_remote_state.egress-peer-node.outputs.bastion_admin_user}"
  egress_bastion_password = "${data.terraform_remote_state.egress-peer-node.outputs.bastion_admin_password}"
}

#
# Backend state
#
terraform {
  backend "s3" {
    key = "test/cloud-peering"
  }
}
