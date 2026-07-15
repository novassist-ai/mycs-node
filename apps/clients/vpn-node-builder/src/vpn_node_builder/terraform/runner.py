"""Terraform subprocess runner."""

from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from pathlib import Path

from vpn_node_builder.core.process import CommandResult, run_cmd, run_cmd_tee


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


def run_terraform_tee(
    args: Sequence[str],
    *,
    template_dir: Path,
    work_dir: Path,
    environ: Mapping[str, str],
    log_path: Path,
    check: bool = True,
    line_filter: Callable[[str], str | None] | None = None,
) -> CommandResult:
    """Run terraform while teeing output to ``log_path`` (bash apply/destroy parity)."""
    cmd = ["terraform", f"-chdir={template_dir}", *args]
    return run_cmd_tee(
        cmd,
        log_path=log_path,
        environ=terraform_env(work_dir, environ),
        cwd=str(work_dir),
        check=check,
        line_filter=line_filter,
    )
