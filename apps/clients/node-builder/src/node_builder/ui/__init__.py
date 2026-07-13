"""Rich UI helpers."""

from __future__ import annotations

from rich.console import Console
from rich.table import Table

from node_builder.cloud.nodes import NodeRecord

console = Console()


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
