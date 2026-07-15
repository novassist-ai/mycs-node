"""Command usage banners (parity with spacenode-cookbook ``common-usage``)."""

from __future__ import annotations

from collections.abc import Callable

from vpn_node_builder.core.workspace import PLACEHOLDER_CLOUD, PLACEHOLDER_NODE_TYPE


def usage_deploy_node(
    node_type: str = PLACEHOLDER_NODE_TYPE,
    cloud: str = PLACEHOLDER_CLOUD,
) -> str:
    return (
        f"\nUSAGE: vpnb deploy-node {node_type} {cloud} "
        "[-r|--region <REGION>] [-c|--clean] [-i|--init] [-u|--upgrade] "
        "[-b|--rebuild] [-a|--no-idle-shutdown] [-s|--show] [-d|--debug]\n\n"
        "  This CLI command creates a node in the given region.\n\n"
        "  -r|--region <REGION>   The region to create the server in\n"
        "  -c|--clean             Clean the Terraform workspace context before deploying\n"
        "  -i|--init              Re-initialize Terraform workspace context before deploying\n"
        "  -u|--upgrade           Rebuild the bastion VM (keeps the data store volume)\n"
        "  -b|--rebuild           Rebuild the bastion VM and replace its data store volume\n"
        "  -a|--no-idle-shutdown  Do not shut down the node when idle\n"
        "  -s|--show              Show cloud resources to be created or changed but do not deploy\n"
        "  -d|--debug             Enable trace output\n"
    )


def usage_reinit_node(
    node_type: str = PLACEHOLDER_NODE_TYPE,
    cloud: str = PLACEHOLDER_CLOUD,
) -> str:
    return (
        f"\nUSAGE: vpnb reinit-node {node_type} {cloud} "
        "[-r|--region <REGION>] [-d|--debug]\n\n"
        "  This CLI command reinitializes the remote state of a node in the given\n"
        "  region.\n\n"
        "  -r|--region <REGION>  The region where the node is deployed\n"
        "  -d|--debug            Enable trace output\n"
    )


def usage_destroy_node(
    node_type: str = PLACEHOLDER_NODE_TYPE,
    cloud: str = PLACEHOLDER_CLOUD,
) -> str:
    return (
        f"\nUSAGE: vpnb destroy-node {node_type} {cloud} "
        "[-r|--region <REGION>] [-x|--delete-remote-state] [-d|--debug]\n\n"
        "  This CLI command destroys a node that has been deployed to the given region.\n\n"
        "  -r|--region <REGION>         The region where the node to be destroyed is deployed\n"
        "  -x|--delete-remote-state     Delete the remote Terraform state bucket/container "
        "after destroy\n"
        "  -d|--debug                   Enable trace output\n"
    )


def usage_download_vpn_config(
    node_type: str = PLACEHOLDER_NODE_TYPE,
    cloud: str = PLACEHOLDER_CLOUD,
) -> str:
    return (
        f"\nUSAGE: vpnb download-vpn-config {node_type} {cloud} "
        "[-r|--region <REGION>] [-u|--user <USERNAME>] [-p|--password <PASSWORD>] "
        "[-d|--debug]\n\n"
        "  This CLI command downloads the VPN client configuration from the bastion\n"
        "  server deployed to a given region.\n\n"
        "  -r|--region <REGION>      The region of the server from which the configuration should be downloaded\n"
        "  -u|--user <USERNAME>      The name of the VPN user whose client configuration should be downloaded\n"
        "  -p|--password <PASSWORD>  The password of the VPN user\n"
        "  -d|--debug                Enable trace output\n"
    )


def usage_start_tunnel(
    node_type: str = PLACEHOLDER_NODE_TYPE,
    cloud: str = PLACEHOLDER_CLOUD,
) -> str:
    return (
        f"\nUSAGE: vpnb start-tunnel {node_type} {cloud} "
        "[-r|--region <REGION>] [-t|--type <TUNNEL_TYPE>] [-d|--debug]\n\n"
        "  This CLI command starts tunnel services which obfuscate VPN traffic to a\n"
        "  bastion node.\n\n"
        "  -r|--region <REGION>       The region where the node is deployed\n"
        "  -t|--type <TUNNEL_TYPE>    The type of tunnel. This should be one of:\n\n"
        "                             - udp_over_tcp\n"
        "                             - udp_over_icmp\n"
        "                             - udp_over_udp\n"
        "                             - udp_over_udp_with_fec\n"
        "                             - tcp_over_udp_with_fec\n\n"
        "  -d|--debug                 Enable trace output\n"
    )


USAGE_BY_COMMAND: dict[str, Callable[..., str]] = {
    "deploy_node": usage_deploy_node,
    "reinit_node": usage_reinit_node,
    "destroy_node": usage_destroy_node,
    "download_vpn_config": usage_download_vpn_config,
    "start_tunnel": usage_start_tunnel,
}


def usage_for(
    command: str,
    *,
    node_type: str = PLACEHOLDER_NODE_TYPE,
    cloud: str = PLACEHOLDER_CLOUD,
) -> str:
    builder = USAGE_BY_COMMAND.get(command)
    if builder is None:
        return ""
    return builder(node_type=node_type, cloud=cloud)
