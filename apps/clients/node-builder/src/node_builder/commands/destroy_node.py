"""``nb destroy-node`` and ``nb reinit-node``."""

from __future__ import annotations

import typer
from rich.console import Console

from node_builder.commands._context import (
    load_input_vars,
    prepare_command_context,
    require_run_dir,
    resolve_deployment,
)
from node_builder.core.errors import NodeBuilderError
from node_builder.terraform.lifecycle import terraform_destroy, terraform_init
from node_builder.terraform.region import set_cloud_region

console = Console()


def destroy_node(
    node_type: str = typer.Argument(...),
    cloud: str = typer.Argument(...),
    region: str | None = typer.Option(None, "-r", "--region"),
    debug: bool = typer.Option(False, "-d", "--debug", hidden=True),
) -> None:
    """Destroy a deployed node."""
    _ = debug
    try:
        ctx = prepare_command_context()
        validated, run_dir = resolve_deployment(
            ctx, node_type=node_type, cloud=cloud, region=region
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
    except NodeBuilderError as exc:
        console.print(f"[red]ERROR![/red] {exc}")
        raise typer.Exit(code=1) from exc


def reinit_node(
    node_type: str = typer.Argument(...),
    cloud: str = typer.Argument(...),
    region: str | None = typer.Option(None, "-r", "--region"),
    debug: bool = typer.Option(False, "-d", "--debug", hidden=True),
) -> None:
    """Re-initialize Terraform remote state for a node."""
    _ = debug
    try:
        ctx = prepare_command_context()
        validated, run_dir = resolve_deployment(
            ctx, node_type=node_type, cloud=cloud, region=region
        )
        require_run_dir(run_dir)
        env = ctx.environ
        env["TF_VAR_cb_local_state_path"] = str(run_dir / "state")
        env["TF_VAR_vpn_idle_action"] = ""
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
    except NodeBuilderError as exc:
        console.print(f"[red]ERROR![/red] {exc}")
        raise typer.Exit(code=1) from exc
