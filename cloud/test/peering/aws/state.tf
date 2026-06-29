#
# Node remote states
#

# Ingress node state
data "terraform_remote_state" "ingress-peer-node" {
  backend = "s3"

  config = {
    key    = "test/cloud-inceptor"
    bucket = "tfstate-${var.peer_node_ingress_region}"
    region = "${var.peer_node_ingress_region}"
  }
}

# Egress node state
data "terraform_remote_state" "egress-peer-node" {
  backend = "s3"

  config = {
    key    = "test/cloud-inceptor"
    bucket = "tfstate-${var.peer_node_egress_region}"
    region = "${var.peer_node_egress_region}"
  }
}
