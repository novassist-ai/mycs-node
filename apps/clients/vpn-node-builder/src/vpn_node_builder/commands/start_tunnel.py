"""``vpnb start-tunnel`` — start VPN obfuscation tunnel client."""

from __future__ import annotations

import json
import subprocess
import time

import typer
from rich.console import Console

from vpn_node_builder.cloud.nodes import get_node_state
from vpn_node_builder.cloud.power import start_node
from vpn_node_builder.commands._context import (
    prepare_command_context,
    require_run_dir,
    resolve_deployment,
)
from vpn_node_builder.core.debug import set_debug
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.workspace import PLACEHOLDER_CLOUD, PLACEHOLDER_NODE_TYPE
from vpn_node_builder.ui import print_cli_error

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
    node_type: str = typer.Argument(
        PLACEHOLDER_NODE_TYPE,
        help=(
            "Node type / recipe family (lists available types if omitted). "
            "Required by vpnb to locate the deployment (bash snb only took CLOUD)."
        ),
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
    tunnel_type: str | None = typer.Option(
        None,
        "-t",
        "--type",
        help=(
            "Tunnel type: udp_over_tcp | udp_over_icmp | udp_over_udp | "
            "udp_over_udp_with_fec | tcp_over_udp_with_fec"
        ),
    ),
    debug: bool = typer.Option(
        False,
        "-d",
        "--debug",
        help="Enable trace output",
    ),
) -> None:
    """Start tunnel services that obfuscate VPN traffic to a bastion node.

    Available for ``wg`` and ``ovpn`` VPN types.
    """
    set_debug(debug)
    try:
        ctx = prepare_command_context()
        validated, run_dir = resolve_deployment(
            ctx,
            node_type=node_type,
            cloud=cloud,
            region=region,
            command="start_tunnel",
        )
        if not tunnel_type:
            raise VpnNodeBuilderError(
                "Please provide a tunnel type. Expected one of: "
                + ", ".join(sorted(TUNNEL_TYPES))
            )
        if tunnel_type not in TUNNEL_TYPES:
            raise VpnNodeBuilderError(
                "Invalid tunnel type. Expected one of: "
                + ", ".join(sorted(TUNNEL_TYPES))
            )
        _ = validated
        require_run_dir(run_dir)
        output_path = run_dir / "output.json"
        if not output_path.is_file():
            raise VpnNodeBuilderError(
                "Deployment workspace path does not exist or is incomplete."
            )
        tunnel_script = run_dir / "client_tunnel"
        if not tunnel_script.is_file():
            raise VpnNodeBuilderError(
                'The client tunnel script has not been retrieved. '
                'Run "vpnb download-vpn-config" for this node first.'
            )

        data = json.loads(output_path.read_text(encoding="utf-8"))
        masking = str((data.get("cb_vpn_masking_available") or {}).get("value") or "")
        # Accept both "true"/"yes" (bash was inconsistent across commands).
        if masking.lower() not in {"true", "yes"}:
            raise VpnNodeBuilderError(
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
            raise VpnNodeBuilderError(
                f'Node is not running. Current state of node is "{state}".'
            )

        subprocess.run([str(tunnel_script), tunnel_type], check=False)
    except VpnNodeBuilderError as exc:
        print_cli_error(exc)
        raise typer.Exit(code=1) from exc
