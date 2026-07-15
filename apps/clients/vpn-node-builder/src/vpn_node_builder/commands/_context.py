"""Shared preamble helpers for vpn-node-builder commands."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from vpn_node_builder.cloud.credentials import CloudSession
from vpn_node_builder.core.environment import validate_environment
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.eula import check_eula
from vpn_node_builder.core.usage import usage_for
from vpn_node_builder.core.workspace import (
    PLACEHOLDER_CLOUD,
    PLACEHOLDER_NODE_TYPE,
    ValidatedWorkspace,
    WorkspaceContext,
    cloud_requires_region,
    set_working_dir,
    validate_workspace,
)


@dataclass
class CommandContext:
    workspace: WorkspaceContext
    environ: dict[str, str]
    session: CloudSession


def prepare_command_context(
    *,
    require_tools: bool = True,
    cwd: Path | None = None,
) -> CommandContext:
    """Workspace + EULA + (optional) environment validation."""
    work = set_working_dir(cwd=cwd or Path.cwd())
    check_eula(work.workspace_root)
    environ = dict(os.environ)
    if require_tools:
        environ = validate_environment(work.working_dir, apply_to_environ=True)
    session = CloudSession()
    session.bind_environ(environ)
    return CommandContext(workspace=work, environ=environ, session=session)


def normalize_deployment_args(
    node_type: str | None,
    cloud: str | None,
) -> tuple[str, str]:
    """Apply bash-style placeholders when positionals are omitted."""
    return (
        node_type if node_type else PLACEHOLDER_NODE_TYPE,
        cloud if cloud else PLACEHOLDER_CLOUD,
    )


def resolve_deployment(
    ctx: CommandContext,
    *,
    node_type: str | None,
    cloud: str | None,
    region: str | None,
    command: str = "deploy_node",
) -> tuple[ValidatedWorkspace, Path]:
    """Validate recipe and return (validated, run_dir).

    Matches spacenode-cookbook order: resolve NODE_TYPE/CLOUD (listing options
    when missing/invalid), then require REGION for region-aware clouds.
    """
    node_type, cloud = normalize_deployment_args(node_type, cloud)
    usage = usage_for(command, node_type=node_type, cloud=cloud)

    # Bash ``common::validate_workspace`` runs before the region check.
    validated = validate_workspace(
        ctx.workspace,
        node_type=node_type,
        cloud=cloud,
        region=region,
        environ=ctx.environ,
        usage=usage,
    )

    if cloud_requires_region(cloud, ctx.environ) and not region:
        raise VpnNodeBuilderError(
            _missing_region_message(ctx, cloud),
            usage=usage,
            soft=True,
        )

    run_dir = (
        validated.workspace_dir / region
        if cloud_requires_region(cloud, ctx.environ) and region
        else validated.workspace_dir
    )
    return validated, run_dir


def _missing_region_message(ctx: CommandContext, cloud: str) -> str:
    """Bash parity: ask for a region and print the show-regions listing."""
    header = "Please provide a cloud region from the following list."
    try:
        from vpn_node_builder.cloud.regions import list_regions

        regions = list_regions(cloud, session=ctx.session, environ=ctx.environ)
    except VpnNodeBuilderError:
        return (
            f"{header}\n\n"
            f'(Could not list regions — run "vpnb show-regions {cloud}".)'
        )
    except Exception:
        return (
            f"{header}\n\n"
            f'Run "vpnb show-regions {cloud}" for available regions.'
        )

    listing = "\n".join(regions) if regions else "(none)"
    return f"{header}\n\n{listing}"


def require_run_dir(run_dir: Path) -> None:
    if not run_dir.is_dir():
        raise VpnNodeBuilderError(
            "Deployment workspace path does not exist. "
            "The server may not have been deployed."
        )


def load_input_vars(run_dir: Path, environ: dict[str, str]) -> None:
    """Merge ``input-vars.sh`` exports into environ if present (bash-sourced)."""
    path = run_dir / "input-vars.sh"
    if path.is_file():
        from vpn_node_builder.core.environment import source_shell_files

        environ.update(source_shell_files([path], environ=environ))
