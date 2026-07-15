"""Developer/runtime diagnostics command."""

from __future__ import annotations

import os
from pathlib import Path

import typer
from rich.console import Console

from vpn_node_builder.core.environment import (
    BUILD_VARS_FILENAME,
    CLOUD_CREDS_FILENAME,
    check_tools,
)
from vpn_node_builder.core.eula import is_eula_accepted
from vpn_node_builder.core.paths import PathContext, resolve_paths
from vpn_node_builder.core.workspace import set_working_dir

console = Console()


def doctor() -> None:
    """Show resolved paths and basic environment information (soft checks)."""
    cwd = Path.cwd()
    paths: PathContext = resolve_paths(cwd=cwd)
    workspace = set_working_dir(cwd=cwd)

    console.print("[bold]vpn-node-builder doctor[/bold]")
    console.print(f"  repo root:      {paths.repo_root or '(not detected)'}")
    console.print(f"  cookbook root:  {paths.cookbook_root}")
    console.print(f"  recipes root:   {paths.recipes_root}")
    console.print(f"  work mount:     {paths.work_mount}")
    console.print(f"  utils bin:      {paths.utils_bin or '(not detected)'}")
    console.print(f"  working dir:    {workspace.working_dir}")
    console.print(f"  workspace root: {workspace.workspace_root}")
    console.print(f"  template dir:   {workspace.template_dir}")
    console.print(
        f"  eula accepted:  {'yes' if is_eula_accepted(workspace.workspace_root) else 'no'}"
    )

    creds = cwd / CLOUD_CREDS_FILENAME
    build_vars = cwd / BUILD_VARS_FILENAME
    console.print(
        f"  cloud-creds.sh: {'present' if creds.is_file() else 'missing'} ({creds})"
    )
    console.print(
        f"  build-vars.sh:  {'present' if build_vars.is_file() else 'missing'} ({build_vars})"
    )

    console.print("  tools:")
    for status in check_tools(path_env=os.environ.get("PATH")):
        mark = "ok" if status.present else "MISSING"
        detail = status.path or status.install_url
        console.print(f"    - {status.name}: {mark} ({detail})")

    typer.echo("OK")
