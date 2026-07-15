"""Subprocess helpers shared by terraform and cloud modules."""

from __future__ import annotations

import subprocess
import sys
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from vpn_node_builder.core.debug import is_debug
from vpn_node_builder.core.errors import VpnNodeBuilderError


@dataclass(frozen=True)
class CommandResult:
    args: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


class ConsoleFilter(Protocol):
    def feed(self, line: str) -> Sequence[str]: ...

    def flush(self) -> Sequence[str]: ...


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
    if is_debug():
        print(f"+ {' '.join(args)}", file=sys.stderr, flush=True)

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
        raise VpnNodeBuilderError(
            f"Command failed ({result.returncode}): {joined}"
            + (f"\n{detail}" if detail else "")
        )
    return result


def run_cmd_tee(
    args: Sequence[str],
    *,
    log_path: Path,
    environ: Mapping[str, str] | None = None,
    cwd: str | None = None,
    check: bool = True,
    console_filter: ConsoleFilter | None = None,
) -> CommandResult:
    """Run a command, tee combined stdout/stderr to ``log_path``, print filtered lines.

    ``console_filter`` only affects the console; the log always stores the raw
    stream. Filters may buffer lines and must be flushed at EOF.
    """
    if is_debug():
        print(f"+ {' '.join(args)}", file=sys.stderr, flush=True)

    env = dict(environ) if environ is not None else None
    log_path.parent.mkdir(parents=True, exist_ok=True)
    recorded: list[str] = []

    with (
        log_path.open("w", encoding="utf-8") as log_file,
        subprocess.Popen(
            list(args),
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        ) as proc,
    ):
        assert proc.stdout is not None
        for raw in proc.stdout:
            log_file.write(raw)
            recorded.append(raw)
            line = raw.rstrip("\n")
            if console_filter is None:
                print(line, flush=True)
            else:
                for kept in console_filter.feed(line):
                    print(kept, flush=True)
        if console_filter is not None:
            for kept in console_filter.flush():
                print(kept, flush=True)
        returncode = proc.wait()

    result = CommandResult(
        args=tuple(args),
        returncode=returncode,
        stdout="".join(recorded),
        stderr="",
    )
    if check and result.returncode != 0:
        detail = result.stdout.strip()
        joined = " ".join(args)
        raise VpnNodeBuilderError(
            f"Command failed ({result.returncode}): {joined}"
            + (f"\n{detail}" if detail else "")
        )
    return result
