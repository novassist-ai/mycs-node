"""``vpnb destroy-node`` and ``vpnb reinit-node``."""

from __future__ import annotations

import typer
from rich.console import Console

from vpn_node_builder.commands._context import (
    load_input_vars,
    prepare_command_context,
    require_run_dir,
    resolve_deployment,
)
from vpn_node_builder.core.cli_options import resolve_option
from vpn_node_builder.core.debug import set_debug
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.workspace import PLACEHOLDER_CLOUD, PLACEHOLDER_NODE_TYPE
from vpn_node_builder.terraform.lifecycle import terraform_destroy, terraform_init
from vpn_node_builder.terraform.region import set_cloud_region
from vpn_node_builder.ui import print_cli_error

console = Console()


def destroy_node(
    node_type: str = typer.Argument(
        PLACEHOLDER_NODE_TYPE,
        help="Node type / recipe family (lists available types if omitted)",
    ),
    cloud: str = typer.Argument(
        PLACEHOLDER_CLOUD,
        help="Cloud target (lists targets if omitted)",
    ),
    region: str | None = typer.Option(
        None,
        "-r",
        "--region",
        help="The region where the node to be destroyed is deployed",
    ),
    debug: bool = typer.Option(
        False,
        "-d",
        "--debug",
        help="Enable trace output",
    ),
) -> None:
    """Destroy a node that has been deployed to the given region."""
    region = resolve_option(region, None)
    debug = resolve_option(debug, False)
    set_debug(debug)
    try:
        ctx = prepare_command_context()
        validated, run_dir = resolve_deployment(
            ctx,
            node_type=node_type,
            cloud=cloud,
            region=region,
            command="destroy_node",
        )
        require_run_dir(run_dir)
        env = ctx.environ
        env["TF_VAR_cb_local_state_path"] = str(run_dir / "state")
        load_input_vars(run_dir, env)
        set_cloud_region(
            cloud,
            region,
            backend=validated.backend,
            session=ctx.session,
            environ=env,
        )
        terraform_destroy(
            template_dir=validated.template_dir,
            work_dir=run_dir,
            environ=env,
        )
        console.print("[green]Destroy completed.[/green]")
    except VpnNodeBuilderError as exc:
        print_cli_error(exc)
        raise typer.Exit(code=1) from exc


def reinit_node(
    node_type: str = typer.Argument(
        PLACEHOLDER_NODE_TYPE,
        help="Node type / recipe family (lists available types if omitted)",
    ),
    cloud: str = typer.Argument(
        PLACEHOLDER_CLOUD,
        help="Cloud target (lists targets if omitted)",
    ),
    region: str | None = typer.Option(
        None,
        "-r",
        "--region",
        help="The region where the node is deployed",
    ),
    debug: bool = typer.Option(
        False,
        "-d",
        "--debug",
        help="Enable trace output",
    ),
) -> None:
    """Re-initialize the remote Terraform state of a node in the given region."""
    region = resolve_option(region, None)
    debug = resolve_option(debug, False)
    set_debug(debug)
    try:
        ctx = prepare_command_context()
        validated, run_dir = resolve_deployment(
            ctx,
            node_type=node_type,
            cloud=cloud,
            region=region,
            command="reinit_node",
        )
        require_run_dir(run_dir)
        env = ctx.environ
        env["TF_VAR_cb_local_state_path"] = str(run_dir / "state")
        env["TF_VAR_idle_action"] = ""
        set_cloud_region(
            cloud,
            region,
            backend=validated.backend,
            session=ctx.session,
            environ=env,
        )
        terraform_init(
            node_type=validated.node_type,
            cloud=cloud,
            region=region,
            template_dir=validated.template_dir,
            work_dir=run_dir,
            backend=validated.backend,
            session=ctx.session,
            environ=env,
        )
        console.print("[green]Reinit completed.[/green]")
    except VpnNodeBuilderError as exc:
        print_cli_error(exc)
        raise typer.Exit(code=1) from exc
