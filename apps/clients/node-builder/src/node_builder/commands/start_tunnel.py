"""``nb start-tunnel`` — start VPN obfuscation tunnel client."""

from __future__ import annotations

import json
import subprocess
import time

import typer
from rich.console import Console

from node_builder.cloud.nodes import get_node_state
from node_builder.cloud.power import start_node
from node_builder.commands._context import (
    prepare_command_context,
    require_run_dir,
    resolve_deployment,
)
from node_builder.core.errors import NodeBuilderError

console = Console()

TUNNEL_TYPES = frozenset(
    {
        "udp_over_tcp",
        "udp_over_icmp",
        "udp_over_udp",
        "udp_over_udp_with_fec",
        "tcp_over_udp_with_fec",
    }
)


def start_tunnel(
    node_type: str = typer.Argument(..., help="Node type (required; fixed vs old CLI)"),
    cloud: str = typer.Argument(...),
    region: str | None = typer.Option(None, "-r", "--region"),
    tunnel_type: str = typer.Option(..., "-t", "--type"),
    debug: bool = typer.Option(False, "-d", "--debug", hidden=True),
) -> None:
    """Start tunnel services that obfuscate VPN traffic to a node.

    Requires ``NODE_TYPE`` and ``CLOUD`` (the former bash command omitted
    ``NODE_TYPE``, which broke workspace resolution).
    """
    _ = debug
    try:
        if tunnel_type not in TUNNEL_TYPES:
            raise NodeBuilderError(
                "Invalid tunnel type. Expected one of: "
                + ", ".join(sorted(TUNNEL_TYPES))
            )
        ctx = prepare_command_context()
        validated, run_dir = resolve_deployment(
            ctx, node_type=node_type, cloud=cloud, region=region
        )
        _ = validated
        require_run_dir(run_dir)
        output_path = run_dir / "output.json"
        if not output_path.is_file():
            raise NodeBuilderError(
                "Deployment workspace path does not exist or is incomplete."
            )
        tunnel_script = run_dir / "client_tunnel"
        if not tunnel_script.is_file():
            raise NodeBuilderError(
                'The client tunnel script has not been retrieved. '
                'Run "nb download-vpn-config" for this node first.'
            )

        data = json.loads(output_path.read_text(encoding="utf-8"))
        masking = str((data.get("cb_vpn_masking_available") or {}).get("value") or "")
        # Accept both "true"/"yes" (bash was inconsistent across commands).
        if masking.lower() not in {"true", "yes"}:
            raise NodeBuilderError(
                "Node does not provide a VPN with a masking service."
            )

        first = (data.get("cb_managed_instances", {}).get("value") or [{}])[0]
        instance_id = str(first.get("id") or "")
        state = get_node_state(
            cloud,
            region or "",
            instance_id,
            session=ctx.session,
            environ=ctx.environ,
        )
        if state == "stopped":
            console.print("\n[green bold]Node is not running. Starting it.[/green bold]", end="")
            start_node(
                cloud,
                region or "",
                instance_id,
                session=ctx.session,
                environ=ctx.environ,
            )
            for _ in range(24):
                time.sleep(5)
                state = get_node_state(
                    cloud,
                    region or "",
                    instance_id,
                    session=ctx.session,
                    environ=ctx.environ,
                )
                console.print(".", end="")
                if state == "running":
                    break
            console.print()

        if state != "running":
            raise NodeBuilderError(
                f'Node is not running. Current state of node is "{state}".'
            )

        subprocess.run([str(tunnel_script), tunnel_type], check=False)
    except NodeBuilderError as exc:
        console.print(f"[red]ERROR![/red] {exc}")
        raise typer.Exit(code=1) from exc
