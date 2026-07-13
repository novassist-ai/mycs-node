"""Subprocess helpers shared by terraform and cloud modules."""

from __future__ import annotations

import subprocess
from collections.abc import Mapping, Sequence
from dataclasses import dataclass

from node_builder.core.errors import NodeBuilderError


@dataclass(frozen=True)
class CommandResult:
    args: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


def run_cmd(
    args: Sequence[str],
    *,
    environ: Mapping[str, str] | None = None,
    cwd: str | None = None,
    check: bool = True,
    capture: bool = True,
) -> CommandResult:
    """Run an external command.

    When ``capture`` is false, stdout/stderr are inherited (streaming).
    """
    completed = subprocess.run(
        list(args),
        cwd=cwd,
        env=dict(environ) if environ is not None else None,
        check=False,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    result = CommandResult(
        args=tuple(args),
        returncode=completed.returncode,
        stdout=completed.stdout or "",
        stderr=completed.stderr or "",
    )
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        joined = " ".join(args)
        raise NodeBuilderError(
            f"Command failed ({result.returncode}): {joined}"
            + (f"\n{detail}" if detail else "")
        )
    return result
