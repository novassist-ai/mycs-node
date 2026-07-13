"""Tool and control-file environment validation."""

from __future__ import annotations

import os
import re
import shutil
from dataclasses import dataclass
from pathlib import Path

from node_builder.core.errors import NodeBuilderError

REQUIRED_TOOLS: tuple[tuple[str, str], ...] = (
    (
        "aws",
        "https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html",
    ),
    (
        "az",
        "https://docs.microsoft.com/en-us/cli/azure/install-azure-cli",
    ),
    (
        "gcloud",
        "https://cloud.google.com/sdk/docs",
    ),
    (
        "terraform",
        "https://www.terraform.io/downloads.html",
    ),
    (
        "jq",
        "https://stedolan.github.io/jq/",
    ),
)

CLOUD_CREDS_FILENAME = "cloud-creds.sh"
BUILD_VARS_FILENAME = "build-vars.sh"

_EXPORT_RE = re.compile(
    r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$"
)


@dataclass(frozen=True)
class ToolStatus:
    name: str
    present: bool
    path: str | None
    install_url: str


def which(tool: str, *, path_env: str | None = None) -> str | None:
    return shutil.which(tool, path=path_env)


def check_tools(
    *,
    path_env: str | None = None,
) -> list[ToolStatus]:
    """Soft check: return status for each required tool (never raises)."""
    statuses: list[ToolStatus] = []
    for name, url in REQUIRED_TOOLS:
        resolved = which(name, path_env=path_env)
        statuses.append(
            ToolStatus(
                name=name,
                present=resolved is not None,
                path=resolved,
                install_url=url,
            )
        )
    return statuses


def require_tools(*, path_env: str | None = None) -> None:
    """Hard check: raise if any required tool is missing."""
    for status in check_tools(path_env=path_env):
        if status.present:
            continue
        raise NodeBuilderError(
            f'Unable to find "{status.name}" in the system path.\n'
            f"Install it from: {status.install_url}"
        )


def parse_shell_exports(text: str) -> dict[str, str]:
    """Parse simple ``export KEY=value`` lines from a shell control file.

    Supports optional quotes. Does not execute shell expansions.
    """
    result: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        match = _EXPORT_RE.match(line)
        if not match:
            continue
        key, value = match.group(1), match.group(2).strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        result[key] = value
    return result


def load_shell_exports(path: Path) -> dict[str, str]:
    return parse_shell_exports(path.read_text(encoding="utf-8"))


def require_control_files(cwd: Path) -> tuple[Path, Path]:
    creds = cwd / CLOUD_CREDS_FILENAME
    build_vars = cwd / BUILD_VARS_FILENAME
    if not creds.is_file():
        raise NodeBuilderError(
            f'Unable to find the Cloud Credentials file at "./{CLOUD_CREDS_FILENAME}".'
        )
    if not build_vars.is_file():
        raise NodeBuilderError(
            f'Unable to find the Deployment variables file at "./{BUILD_VARS_FILENAME}".'
        )
    return creds, build_vars


def validate_environment(
    cwd: Path | None = None,
    *,
    environ: dict[str, str] | None = None,
    path_env: str | None = None,
    apply_to_environ: bool = True,
) -> dict[str, str]:
    """Validate tools + control files and return merged environment values.

    When ``apply_to_environ`` is true and ``environ`` is omitted, loaded values
    are written into ``os.environ``.
    """
    work_cwd = (cwd or Path.cwd()).resolve()
    require_tools(path_env=path_env)
    creds_path, build_vars_path = require_control_files(work_cwd)

    merged = dict(environ) if environ is not None else dict(os.environ)
    merged.update(load_shell_exports(creds_path))
    merged.update(load_shell_exports(build_vars_path))

    if apply_to_environ and environ is None:
        os.environ.update(merged)

    return merged
