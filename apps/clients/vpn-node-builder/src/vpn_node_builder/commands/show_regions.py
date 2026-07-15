"""``vpnb show-regions``."""

from __future__ import annotations

import typer
from rich.console import Console

from vpn_node_builder.cloud.regions import list_regions
from vpn_node_builder.commands._context import prepare_command_context
from vpn_node_builder.core.credentials import validate_cloud_credentials
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.ui import print_cli_error

console = Console()

_DOCS = {
    "aws": (
        "Available Amazon Web Services (AWS) Regions",
        "https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RegionsAndAvailabilityZones.html",
    ),
    "azure": (
        "Available Microsoft Azure Regions",
        "https://azure.microsoft.com/en-us/global-infrastructure/locations/",
    ),
    "google": (
        "Available Google Cloud Regions",
        "https://cloud.google.com/compute/docs/regions-zones/",
    ),
}


def show_regions(
    cloud: str = typer.Argument(
        "help",
        help='Cloud to list regions for: "aws", "azure", or "google"',
    ),
) -> None:
    """Show regions that can be targeted for the supported public clouds."""
    try:
        if cloud in {"help", "-h", "--help"}:
            console.print(
                "\nUSAGE: vpnb show-regions <CLOUD>\n\n"
                '  Shows regions that can be targeted for each supported cloud.\n'
                '  Available public clouds: "aws", "azure", and "google".\n'
            )
            raise typer.Exit(code=0)

        ctx = prepare_command_context()
        if cloud not in _DOCS:
            raise VpnNodeBuilderError(
                f'Unknown cloud "{cloud}". Use aws, azure, or google.'
            )
        validate_cloud_credentials(cloud, ctx.environ)
        title, url = _DOCS[cloud]
        regions = list_regions(cloud, session=ctx.session, environ=ctx.environ)
        console.print(f"\n[green]{title}:[/green]\n")
        for name in regions:
            console.print(name)
        console.print("\n[green]More detail can be found at:[/green]")
        console.print(f"[blue]- {url}[/blue]")
    except VpnNodeBuilderError as exc:
        print_cli_error(exc)
        raise typer.Exit(code=1) from exc
