"""Shared preamble helpers for node-builder commands."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from node_builder.cloud.credentials import CloudSession
from node_builder.core.environment import validate_environment
from node_builder.core.errors import NodeBuilderError
from node_builder.core.eula import check_eula
from node_builder.core.workspace import (
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


def resolve_deployment(
    ctx: CommandContext,
    *,
    node_type: str,
    cloud: str,
    region: str | None,
) -> tuple[ValidatedWorkspace, Path]:
    """Validate recipe and return (validated, run_dir)."""
    if cloud_requires_region(cloud, ctx.environ) and not region:
        raise NodeBuilderError(
            f'Region is required for cloud "{cloud}". '
            f'Run "nb show-regions {cloud}" for available regions.'
        )

    validated = validate_workspace(
        ctx.workspace,
        node_type=node_type,
        cloud=cloud,
        region=region,
        environ=ctx.environ,
    )
    run_dir = (
        validated.workspace_dir / region
        if cloud_requires_region(cloud, ctx.environ) and region
        else validated.workspace_dir
    )
    return validated, run_dir


def require_run_dir(run_dir: Path) -> None:
    if not run_dir.is_dir():
        raise NodeBuilderError(
            "Deployment workspace path does not exist. "
            "The server may not have been deployed."
        )


def load_input_vars(run_dir: Path, environ: dict[str, str]) -> None:
    """Merge ``input-vars.sh`` exports into environ if present."""
    path = run_dir / "input-vars.sh"
    if path.is_file():
        from node_builder.core.environment import load_shell_exports

        environ.update(load_shell_exports(path))
