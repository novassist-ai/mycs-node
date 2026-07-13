"""``nb show-regions``."""

from __future__ import annotations

import typer
from rich.console import Console

from node_builder.cloud.regions import list_regions
from node_builder.commands._context import prepare_command_context
from node_builder.core.credentials import validate_cloud_credentials
from node_builder.core.errors import NodeBuilderError

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
    cloud: str = typer.Argument(..., help="Cloud: aws | azure | google"),
) -> None:
    """Show regions nodes can be created in."""
    try:
        ctx = prepare_command_context()
        if cloud not in _DOCS:
            raise NodeBuilderError(
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
    except NodeBuilderError as exc:
        console.print(f"[red]ERROR![/red] {exc}")
        raise typer.Exit(code=1) from exc
