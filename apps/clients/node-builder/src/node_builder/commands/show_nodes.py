"""``nb show-nodes`` — interactive node management."""

from __future__ import annotations

import json
import subprocess
from getpass import getpass

import typer
from rich.console import Console

from node_builder.cloud.nodes import list_nodes
from node_builder.cloud.power import start_node, stop_node
from node_builder.commands._context import prepare_command_context
from node_builder.commands.deploy_node import deploy_node
from node_builder.commands.destroy_node import destroy_node
from node_builder.commands.download_vpn_config import download_vpn_config
from node_builder.core.errors import NodeBuilderError
from node_builder.core.workspace import cloud_requires_region
from node_builder.ui import print_nodes_table

console = Console()


def show_nodes() -> None:
    """Show deployed nodes and run an interactive action menu."""
    try:
        ctx = prepare_command_context()
        nodes = list_nodes(
            ctx.workspace.workspace_root,
            session=ctx.session,
            environ=ctx.environ,
        )
        console.print("\n[green bold]Nodes deployed to the cloud[/green bold]")
        console.print("[green]===========================[/green]\n")
        if not nodes:
            console.print("[green]No nodes have been deployed.[/green]")
            return

        print_nodes_table(nodes)
        choice = typer.prompt(
            "\nSelect node to perform an action on or (q)uit",
            default="q",
        ).strip()
        if choice.lower() in {"", "q"}:
            return
        if not choice.isdigit() or not (0 <= int(choice) < len(nodes)):
            raise NodeBuilderError("Invalid node selected.")

        node = nodes[int(choice)]
        if node.root_user:
            console.print(
                f"\n[cyan]Node Admin =>\n  User: {node.root_user}\n"
                f"  Password: {node.root_passwd}[/cyan]"
            )

        console.print("\n[green bold]What do you want to do:[/green bold]")
        console.print("1) Update Node")
        vpn_ok = node.state == "running" and node.vpn_type in {"openvpn", "ipsec"}
        if vpn_ok:
            console.print("2) Download VPN Config")
        else:
            console.print("[dim]2) Download VPN Config[/dim]")
        if node.state == "running":
            console.print("3) SSH to Node")
            console.print("4) Stop Node")
        elif node.state == "stopped":
            console.print("[dim]3) SSH to Node[/dim]")
            console.print("4) Start Node")
        else:
            console.print("[dim]3) SSH to Node[/dim]")
            console.print("[dim]4) Stop/Start Node[/dim]")
        console.print("5) Delete Node")

        action = typer.prompt("\nSelect action or (q)uit", default="q").strip()
        if action.lower() in {"", "q"}:
            return
        if action not in {"1", "2", "3", "4", "5"}:
            raise NodeBuilderError("Invalid action selected.")

        region_opt = node.region or None
        if action == "1":
            deploy_node(
                node_type=node.node_type,
                cloud=node.cloud,
                region=region_opt,
                upgrade=True,
            )
        elif action == "2":
            if not vpn_ok:
                raise NodeBuilderError("Cannot download VPN config from selected node.")
            username = typer.prompt("Please enter the VPN username")
            password = getpass("Please enter the VPN password: ")
            download_vpn_config(
                node_type=node.node_type,
                cloud=node.cloud,
                region=region_opt,
                user=username,
                password=password,
            )
        elif action == "3":
            if node.state != "running":
                raise NodeBuilderError("Node is not running.")
            _ssh_to_node(ctx.workspace.workspace_root, node)
        elif action == "4":
            if node.state == "running":
                console.print(f'\n[green]Stopping "{node.address}"...[/green]')
                stop_node(
                    node.cloud,
                    node.region,
                    node.managed_instance_id,
                    session=ctx.session,
                    environ=ctx.environ,
                )
            elif node.state == "stopped":
                console.print(f'\n[green]Starting "{node.address}"...[/green]')
                start_node(
                    node.cloud,
                    node.region,
                    node.managed_instance_id,
                    session=ctx.session,
                    environ=ctx.environ,
                )
                deploy_node(
                    node_type=node.node_type,
                    cloud=node.cloud,
                    region=region_opt,
                )
            else:
                raise NodeBuilderError(f'Cannot change power state from "{node.state}".')
        elif action == "5":
            destroy_node(
                node_type=node.node_type,
                cloud=node.cloud,
                region=region_opt,
            )
    except NodeBuilderError as exc:
        console.print(f"[red]ERROR![/red] {exc}")
        raise typer.Exit(code=1) from exc


def _ssh_to_node(workspace_root, node) -> None:
    region_part = node.region if node.region else ""
    if cloud_requires_region(node.cloud) and node.region:
        run_dir = workspace_root / node.node_type / node.cloud / node.region
    else:
        run_dir = workspace_root / node.node_type / node.cloud
    output = json.loads((run_dir / "output.json").read_text(encoding="utf-8"))
    first = (output.get("cb_managed_instances", {}).get("value") or [{}])[0]
    ssh_user = str(first.get("ssh_user") or "")
    name = str(first.get("name") or "")
    key_file = run_dir / f"{name}-ssh-key.pem"
    if ".mycs." in (node.address or ""):
        host = node.instance_ip
    else:
        host = node.address or node.instance_ip
    subprocess.run(
        [
            "ssh",
            "-o",
            "UserKnownHostsFile=/dev/null",
            "-o",
            "StrictHostKeyChecking=no",
            "-i",
            str(key_file),
            f"{ssh_user}@{host}",
        ],
        check=False,
    )
    _ = region_part
