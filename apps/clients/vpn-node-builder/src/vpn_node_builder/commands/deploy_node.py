"""``vpnb deploy-node``."""

from __future__ import annotations

import json
from pathlib import Path

import typer
from rich.console import Console

from vpn_node_builder.commands._context import (
    prepare_command_context,
    resolve_deployment,
)
from vpn_node_builder.core.cli_options import resolve_option
from vpn_node_builder.core.debug import set_debug
from vpn_node_builder.core.environment import source_shell_files
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.workspace import (
    PLACEHOLDER_CLOUD,
    PLACEHOLDER_NODE_TYPE,
    deployment_folder,
)
from vpn_node_builder.terraform.lifecycle import (
    terraform_apply,
    terraform_init,
    terraform_plan,
    terraform_taint_bastion,
)
from vpn_node_builder.terraform.region import set_cloud_region
from vpn_node_builder.ui import print_cli_error

console = Console()


def _write_dependent_inputs(
    *,
    run_dir: Path,
    workspace_root: Path,
    input_node: str,
    input_node_cloud: str,
    region: str | None,
    environ: dict[str, str],
    verbose: bool,
) -> None:
    input_vars = run_dir / "input-vars.sh"
    lines = [f"# inputs from node '{input_node}'"]
    if region:
        output_file = (
            workspace_root / input_node / input_node_cloud / region / "output.json"
        )
    else:
        output_file = workspace_root / input_node / input_node_cloud / "output.json"
    if output_file.is_file():
        data = json.loads(output_file.read_text(encoding="utf-8"))
        for name, entry in data.items():
            val = entry.get("value") if isinstance(entry, dict) else entry
            # Escape single quotes for shell-safe export
            rendered = str(val).replace("'", "'\"'\"'")
            lines.append(f"export TF_VAR_{name}='{rendered}'")
            if verbose:
                console.print(f"  [bold]{name}[/bold] = \"{val}\"")
    input_vars.write_text("\n".join(lines) + "\n", encoding="utf-8")
    environ.update(source_shell_files([input_vars], environ=environ))


def deploy_node(
    node_type: str = typer.Argument(
        PLACEHOLDER_NODE_TYPE,
        help="Node type / recipe family (lists available types if omitted)",
    ),
    cloud: str = typer.Argument(
        PLACEHOLDER_CLOUD,
        help="Cloud target (aws | azure | google | …); lists targets if omitted",
    ),
    region: str | None = typer.Option(
        None,
        "-r",
        "--region",
        help="The region to create the server in",
    ),
    clean: bool = typer.Option(
        False,
        "-c",
        "--clean",
        help="Clean the Terraform workspace context before deploying",
    ),
    init: bool = typer.Option(
        False,
        "-i",
        "--init",
        help="Re-initialize Terraform workspace context before deploying",
    ),
    upgrade: bool = typer.Option(
        False,
        "-u",
        "--upgrade",
        help="Rebuild the bastion VM (keeps the data store volume)",
    ),
    rebuild: bool = typer.Option(
        False,
        "-b",
        "--rebuild",
        help="Rebuild the bastion VM and replace its data store volume",
    ),
    no_idle_shutdown: bool = typer.Option(
        False,
        "-a",
        "--no-idle-shutdown",
        help="Do not shut down the node when idle",
    ),
    show: bool = typer.Option(
        False,
        "-s",
        "--show",
        help="Show cloud resources to be created or changed but do not deploy",
    ),
    debug: bool = typer.Option(
        False,
        "-d",
        "--debug",
        help="Enable trace output",
    ),
    dev: bool = typer.Option(
        False,
        "--dev",
        help="Print dependent-recipe input variables while deploying",
    ),
) -> None:
    """Create or update a VPN node in the given cloud region."""
    region = resolve_option(region, None)
    clean = resolve_option(clean, False)
    init = resolve_option(init, False)
    upgrade = resolve_option(upgrade, False)
    rebuild = resolve_option(rebuild, False)
    no_idle_shutdown = resolve_option(no_idle_shutdown, False)
    show = resolve_option(show, False)
    debug = resolve_option(debug, False)
    dev = resolve_option(dev, False)
    set_debug(debug)
    try:
        ctx = prepare_command_context()
        validated, run_dir = resolve_deployment(
            ctx,
            node_type=node_type,
            cloud=cloud,
            region=region,
            command="deploy_node",
        )
        run_dir.mkdir(parents=True, exist_ok=True)
        env = ctx.environ
        base_name = deployment_folder(validated.workspace)
        env["TF_VAR_cb_local_state_path"] = str(run_dir / "state")

        if no_idle_shutdown:
            env["TF_VAR_idle_action"] = ""
        else:
            output_json = run_dir / "output.json"
            if output_json.is_file():
                data = json.loads(output_json.read_text(encoding="utf-8"))
                idle = data.get("cb_idle_action", {}).get("value", "shutdown")
                env["TF_VAR_idle_action"] = str(idle if idle not in (None, "null") else "shutdown")
            else:
                env["TF_VAR_idle_action"] = "shutdown"

        if validated.input_node and validated.input_node_cloud:
            if dev:
                console.print(
                    f"\n[green bold]Deploying recipe with inputs from node "
                    f"'{validated.input_node}'...[/green bold]\n"
                )
            _write_dependent_inputs(
                run_dir=run_dir,
                workspace_root=validated.workspace.workspace_root,
                input_node=validated.input_node,
                input_node_cloud=validated.input_node_cloud,
                region=region,
                environ=env,
                verbose=dev,
            )

        set_cloud_region(
            cloud,
            region,
            base_name=base_name,
            backend=validated.backend,
            session=ctx.session,
            environ=env,
        )

        tf_dir = run_dir / ".terraform"
        if clean:
            for path in run_dir.glob(".terraform*"):
                if path.is_dir():
                    import shutil

                    shutil.rmtree(path)
                else:
                    path.unlink(missing_ok=True)
            terraform_init(
                node_type=validated.node_type,
                cloud=cloud,
                region=region,
                base_name=base_name,
                template_dir=validated.template_dir,
                work_dir=run_dir,
                backend=validated.backend,
                session=ctx.session,
                environ=env,
            )
        elif init or not tf_dir.exists():
            terraform_init(
                node_type=validated.node_type,
                cloud=cloud,
                region=region,
                base_name=base_name,
                template_dir=validated.template_dir,
                work_dir=run_dir,
                backend=validated.backend,
                session=ctx.session,
                environ=env,
            )

        if rebuild or upgrade:
            terraform_taint_bastion(
                cloud=cloud,
                template_dir=validated.template_dir,
                work_dir=run_dir,
                environ=env,
                include_data_store=rebuild,
            )

        if validated.input_node:
            env.pop("TF_VAR_name", None)

        if show:
            terraform_plan(
                template_dir=validated.template_dir,
                work_dir=run_dir,
                environ=env,
            )
            return

        output_path = terraform_apply(
            template_dir=validated.template_dir,
            work_dir=run_dir,
            environ=env,
        )
        data = json.loads(output_path.read_text(encoding="utf-8"))
        node_description = data.get("cb_node_description", {}).get("value") or ""
        instances = data.get("cb_managed_instances", {}).get("value") or []
        bastion_description = ""
        if instances:
            bastion_description = str(instances[0].get("description") or "")
        console.print(f"\n{node_description}\n\n{bastion_description}")
    except VpnNodeBuilderError as exc:
        print_cli_error(exc)
        raise typer.Exit(code=1) from exc
