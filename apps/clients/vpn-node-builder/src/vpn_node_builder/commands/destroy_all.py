"""``vpnb destroy-all``.

Destroy every deployed node in the workspace and then remove the per-cloud
Terraform state storage (one bucket / storage account per configured cloud).
"""

from __future__ import annotations

import typer
from rich.console import Console

from vpn_node_builder.commands._context import prepare_command_context
from vpn_node_builder.commands.destroy_node import destroy_deployment
from vpn_node_builder.core.cli_options import resolve_option
from vpn_node_builder.core.credentials import REQUIRED_CREDENTIALS
from vpn_node_builder.core.debug import set_debug
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.workspace import deployment_folder, iter_deployed_configs
from vpn_node_builder.terraform.backend import delete_backend_resources
from vpn_node_builder.ui import print_cli_error

console = Console()

# Cloud -> Terraform backend used for its remote state.
_CLOUD_BACKEND = {"aws": "s3", "google": "gcs", "azure": "azurerm"}


def _configured_clouds(environ: dict[str, str]) -> list[str]:
    """Clouds whose required credentials are all present in ``cloud-creds.sh``."""
    configured: list[str] = []
    for cloud, required in REQUIRED_CREDENTIALS.items():
        if all((environ.get(name) or "").strip() for name in required):
            configured.append(cloud)
    return configured


def _format_config(node_type: str, cloud: str, region: str | None) -> str:
    return f"{node_type}/{cloud}" + (f"/{region}" if region else "")


def destroy_all(
    yes: bool = typer.Option(
        False,
        "-y",
        "--yes",
        help="Do not prompt for confirmation before destroying everything",
    ),
    debug: bool = typer.Option(
        False,
        "-d",
        "--debug",
        help="Enable trace output",
    ),
) -> None:
    """Destroy all deployed nodes and delete the workspace state buckets."""
    yes = resolve_option(yes, False)
    debug = resolve_option(debug, False)
    set_debug(debug)
    try:
        ctx = prepare_command_context()
        base_name = deployment_folder(ctx.workspace)
        configs = iter_deployed_configs(ctx.workspace.workspace_root, ctx.environ)
        clouds = _configured_clouds(ctx.environ)

        # State buckets are region-bound, so remove one per (cloud, region)
        # among the configured clouds that were actually deployed.
        state_targets = sorted(
            {
                (cloud, region)
                for _, cloud, region in configs
                if cloud in clouds and cloud in _CLOUD_BACKEND
            }
        )

        if not configs:
            console.print("[yellow]Nothing to destroy in this workspace.[/yellow]")
            return

        console.print("[bold]The following will be destroyed:[/bold]")
        for node_type, cloud, region in configs:
            console.print(f"  - node: {_format_config(node_type, cloud, region)}")
        if state_targets:
            console.print("  - state buckets:")
            for cloud, region in state_targets:
                console.print(f"      {cloud}" + (f"/{region}" if region else ""))

        if not yes and not typer.confirm("\nProceed?", default=False):
            console.print("[yellow]Aborted.[/yellow]")
            raise typer.Exit(code=1)

        failures: list[str] = []
        for node_type, cloud, region in configs:
            label = _format_config(node_type, cloud, region)
            console.print(f"\n[bold]Destroying {label}...[/bold]")
            try:
                # Fresh context per node so per-node env vars do not leak.
                node_ctx = prepare_command_context()
                destroy_deployment(
                    node_ctx, node_type=node_type, cloud=cloud, region=region
                )
                console.print(f"[green]Destroyed {label}.[/green]")
            except VpnNodeBuilderError as exc:
                failures.append(f"{label}: {exc}")
                console.print(f"[red]Failed to destroy {label}: {exc}[/red]")

        if failures:
            console.print(
                "\n[red]Some nodes failed to destroy; leaving state buckets "
                "in place so they can be retried:[/red]"
            )
            for failure in failures:
                console.print(f"  - {failure}")
            raise typer.Exit(code=1)

        console.print("\n[bold]Deleting workspace state buckets...[/bold]")
        for cloud, region in state_targets:
            backend = _CLOUD_BACKEND[cloud]
            label = f"{cloud}" + (f"/{region}" if region else "")
            try:
                deleted = delete_backend_resources(
                    backend,
                    base_name=base_name,
                    region=region,
                    environ=ctx.environ,
                    session=ctx.session,
                )
            except VpnNodeBuilderError as exc:
                console.print(
                    f"[yellow]Could not delete state bucket for {label}: {exc}[/yellow]"
                )
                continue
            if deleted:
                console.print(f"[green]Deleted state storage: {deleted}[/green]")
            else:
                console.print(f"[yellow]No state storage found for {label}.[/yellow]")

        console.print("\n[green]destroy-all completed.[/green]")
    except VpnNodeBuilderError as exc:
        print_cli_error(exc)
        raise typer.Exit(code=1) from exc
