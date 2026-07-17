"""``vpnb destroy-node`` and ``vpnb reinit-node``."""

from __future__ import annotations

import shutil

import typer
from rich.console import Console

from vpn_node_builder.commands._context import (
    CommandContext,
    load_input_vars,
    prepare_command_context,
    require_run_dir,
    resolve_deployment,
)
from vpn_node_builder.core.cli_options import resolve_option
from vpn_node_builder.core.debug import set_debug
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.workspace import (
    PLACEHOLDER_CLOUD,
    PLACEHOLDER_NODE_TYPE,
    deployment_folder,
)
from vpn_node_builder.terraform.backend import backend_state_exists
from vpn_node_builder.terraform.lifecycle import terraform_destroy, terraform_init
from vpn_node_builder.terraform.region import set_cloud_region
from vpn_node_builder.ui import print_cli_error

console = Console()

# Return values of :func:`destroy_deployment`.
DESTROYED = "destroyed"
MISSING_STATE = "missing-state"


def destroy_deployment(
    ctx: CommandContext,
    *,
    node_type: str,
    cloud: str,
    region: str | None,
) -> str:
    """Destroy a single deployed node (shared by ``destroy-node``/``destroy-all``).

    Returns ``DESTROYED`` normally, or ``MISSING_STATE`` when the remote state
    storage the node was initialized with no longer exists (in which case the
    stale local run directory is removed and no destroy is attempted).
    """
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
        base_name=deployment_folder(validated.workspace),
        backend=validated.backend,
        session=ctx.session,
        environ=env,
    )
    if backend_state_exists(run_dir, environ=env, session=ctx.session) is False:
        shutil.rmtree(run_dir, ignore_errors=True)
        return MISSING_STATE
    terraform_destroy(
        template_dir=validated.template_dir,
        work_dir=run_dir,
        environ=env,
    )
    return DESTROYED


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
        status = destroy_deployment(
            ctx, node_type=node_type, cloud=cloud, region=region
        )
        if status == MISSING_STATE:
            console.print(
                "[yellow]Remote state storage no longer exists; nothing to "
                "destroy. Removed the stale local deployment directory (any "
                "leftover cloud resources must be cleaned up manually).[/yellow]"
            )
        else:
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
            base_name=deployment_folder(validated.workspace),
            backend=validated.backend,
            session=ctx.session,
            environ=env,
        )
        terraform_init(
            node_type=validated.node_type,
            cloud=cloud,
            region=region,
            base_name=deployment_folder(validated.workspace),
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
