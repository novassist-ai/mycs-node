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
from vpn_node_builder.core.workspace import (
    WORKSPACE_NAME_ENV,
    deployment_folder,
    deployment_name,
    iter_deployed_configs,
    set_working_dir,
)
from vpn_node_builder.terraform.backend import (
    azure_container_name,
    azure_storage_account_name,
    state_bucket_name,
)

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

    folder = deployment_folder(workspace)
    configs = iter_deployed_configs(workspace.workspace_root)

    name_source = (
        f"{WORKSPACE_NAME_ENV}" if os.environ.get(WORKSPACE_NAME_ENV, "").strip()
        else "working dir name"
    )
    console.print(f"  workspace name: {folder} (from {name_source})")

    console.print("  state storage (derived, region-bound):")
    console.print(f"    - s3 / gcs bucket: vpnb-{folder}-<region>")
    console.print(
        f"    - azure:           account vpnb{folder}<region>, "
        f"container {azure_container_name(folder)}"
    )
    remote = sorted(
        {(c, r) for _, c, r in configs if c in {"aws", "google", "azure"} and r}
    )
    for cloud, region in remote:
        if cloud == "azure":
            location = (
                f"account {azure_storage_account_name(folder, region)}, "
                f"container {azure_container_name(folder)}"
            )
        else:
            location = f"bucket {state_bucket_name(folder, region)}"
        console.print(f"    - {cloud}/{region}: {location}")

    console.print("  vpn vpc names (derived):")
    if configs:
        for node_type, cloud, region in configs:
            location = f"{node_type}/{cloud}" + (f"/{region}" if region else "")
            console.print(
                f"    - {location}: {deployment_name(folder, cloud, region)}"
            )
    else:
        console.print("    - (no deployments found)")

    console.print("  tools:")
    for status in check_tools(path_env=os.environ.get("PATH")):
        mark = "ok" if status.present else "MISSING"
        detail = status.path or status.install_url
        console.print(f"    - {status.name}: {mark} ({detail})")

    typer.echo("OK")
