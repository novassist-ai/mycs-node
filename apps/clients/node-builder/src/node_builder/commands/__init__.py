"""CLI command modules."""

from __future__ import annotations

import typer

from node_builder.commands import (
    deploy_node,
    destroy_node,
    doctor,
    download_vpn_config,
    init,
    show_nodes,
    show_regions,
    start_tunnel,
)


def register_commands(app: typer.Typer) -> None:
    """Attach subcommands to the root Typer application."""
    app.command("init")(init.init_cmd)
    app.command("show-regions")(show_regions.show_regions)
    app.command("deploy-node")(deploy_node.deploy_node)
    app.command("reinit-node")(destroy_node.reinit_node)
    app.command("destroy-node")(destroy_node.destroy_node)
    app.command("download-vpn-config")(download_vpn_config.download_vpn_config)
    app.command("start-tunnel")(start_tunnel.start_tunnel)
    app.command("show-nodes")(show_nodes.show_nodes)
    app.command("doctor")(doctor.doctor)
