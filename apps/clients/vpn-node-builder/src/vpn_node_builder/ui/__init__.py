"""Rich UI helpers."""

from __future__ import annotations

from rich.console import Console
from rich.table import Table

from vpn_node_builder.cloud.nodes import NodeRecord
from vpn_node_builder.core.errors import VpnNodeBuilderError

console = Console()


def print_cli_error(exc: VpnNodeBuilderError) -> None:
    """Print optional usage banner then the error (bash ``usage::*`` parity)."""
    if exc.usage:
        console.print(exc.usage.rstrip())
        console.print()
    if exc.soft:
        console.print(str(exc))
    else:
        console.print(f"[red]ERROR![/red] {exc}")


def print_nodes_table(nodes: list[NodeRecord]) -> None:
    table = Table(show_header=True, header_style="bold")
    table.add_column("#", justify="right")
    table.add_column("Node")
    table.add_column("Cloud")
    table.add_column("Region")
    table.add_column("Address")
    table.add_column("Status")
    table.add_column("Version")
    for i, node in enumerate(nodes):
        table.add_row(
            str(i),
            node.node_type[:30],
            node.cloud,
            node.region or "-",
            (node.address or "")[:40],
            node.state,
            node.version or "-",
        )
    console.print(table)
