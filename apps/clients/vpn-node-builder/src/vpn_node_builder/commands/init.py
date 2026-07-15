"""``vpnb init`` — create workspace control-file stubs."""

from __future__ import annotations

from pathlib import Path

import typer
from rich.console import Console

from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.eula import check_eula
from vpn_node_builder.core.init_files import initialize_control_files
from vpn_node_builder.core.workspace import set_working_dir

console = Console()


def init_cmd() -> None:
    """Initialize the current folder with control files for deployment scripts."""
    try:
        workspace = set_working_dir(cwd=Path.cwd())
        check_eula(workspace.workspace_root)
        result = initialize_control_files(workspace.working_dir)
    except VpnNodeBuilderError as exc:
        console.print(f"[red]ERROR![/red] {exc}")
        raise typer.Exit(code=1) from exc

    console.print("\n[green]Creating control files in current folder...[/green]")
    for name in result.created:
        console.print(f"  [green]created[/green]  {result.working_dir / name}")
    for name in result.skipped:
        console.print(f"  [dim]skipped[/dim]  {result.working_dir / name} (already exists)")

    if not result.created:
        console.print(
            "\n[dim]Nothing to do — control files already present.[/dim]"
        )
    else:
        console.print(
            "\n[green]Edit the new files with your cloud credentials and "
            "deployment settings before running deploy commands.[/green]"
        )
