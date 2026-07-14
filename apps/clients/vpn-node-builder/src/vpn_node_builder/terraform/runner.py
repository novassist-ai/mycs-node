"""Terraform subprocess runner."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from pathlib import Path

from vpn_node_builder.core.process import CommandResult, run_cmd


def terraform_env(
    work_dir: Path,
    environ: Mapping[str, str],
) -> dict[str, str]:
    env = dict(environ)
    env["TF_DATA_DIR"] = str(work_dir / ".terraform")
    return env


def run_terraform(
    args: Sequence[str],
    *,
    template_dir: Path,
    work_dir: Path,
    environ: Mapping[str, str],
    check: bool = True,
    capture: bool = True,
) -> CommandResult:
    cmd = ["terraform", f"-chdir={template_dir}", *args]
    return run_cmd(
        cmd,
        environ=terraform_env(work_dir, environ),
        cwd=str(work_dir),
        check=check,
        capture=capture,
    )
