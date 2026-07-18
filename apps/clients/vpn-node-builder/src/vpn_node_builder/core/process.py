"""Subprocess helpers shared by terraform and cloud modules."""

from __future__ import annotations

import re
import subprocess
import sys
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from vpn_node_builder.core.debug import debug_detail, is_debug
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


def _s3_bucket_from_args(args: Sequence[str]) -> str | None:
    for arg in args:
        if arg.startswith("s3://"):
            return arg.removeprefix("s3://").split("/", 1)[0]
    return None


def friendly_command_error(
    args: Sequence[str],
    *,
    returncode: int,
    detail: str,
) -> str:
    """Map known cloud/CLI failures to concise, actionable messages."""
    joined = " ".join(args)
    text = detail or ""
    lower = text.lower()
    bucket = _s3_bucket_from_args(args)

    # AWS S3 create-bucket races after a recent delete (global name reuse delay).
    if (
        "operationaborted" in lower
        or "conflicting conditional operation" in lower
    ) and (
        "s3" in args
        and ("mb" in args or "create-bucket" in joined)
    ):
        name = bucket or "the requested bucket"
        return (
            f"Could not create S3 bucket {name!r}: AWS reports a conflicting "
            "operation in progress. This usually means the bucket was deleted "
            "recently and the name is not reusable yet. Wait a few minutes and "
            "retry."
        )

    if "bucketalreadyexists" in lower.replace(" ", ""):
        name = bucket or "the requested bucket"
        return (
            f"S3 bucket {name!r} already exists in another AWS account "
            "(bucket names are globally unique). Choose a different workspace "
            "name (VPNB_WORKSPACE_NAME) or wait if you just deleted a bucket "
            "with this name."
        )

    if "bucketalreadyownedbyyou" in lower.replace(" ", ""):
        name = bucket or "the requested bucket"
        return (
            f"S3 bucket {name!r} already exists in this account. "
            "Re-run with -i/--init if Terraform needs to reconfigure the backend."
        )

    if "nosuchbucket" in lower.replace(" ", ""):
        name = bucket or "the requested bucket"
        return (
            f"S3 bucket {name!r} does not exist. It may have been deleted; "
            "re-run with -i/--init to recreate state storage."
        )

    if "invalidaccesskeyid" in lower.replace(" ", "") or (
        "authfailure" in lower.replace(" ", "") and "aws" in args
    ):
        return (
            "AWS authentication failed. Check AWS_ACCESS_KEY / AWS_SECRET_KEY "
            "in cloud-creds.sh."
        )

    if "accessdenied" in lower.replace(" ", "") and "aws" in args:
        return (
            "AWS AccessDenied for this operation. The credentials in "
            "cloud-creds.sh may lack permission to manage S3 or EC2 resources."
        )

    if "az" in args and (
        "aadsts" in lower or "authentication failed" in lower or "login failed" in lower
    ):
        return (
            "Azure authentication failed. Check ARM_CLIENT_ID, "
            "ARM_CLIENT_SECRET, and ARM_TENANT_ID in cloud-creds.sh."
        )

    if "gcloud" in args and (
        "could not read json" in lower
        or "not authenticated" in lower
        or "reauthentication failed" in lower
    ):
        return (
            "Google Cloud authentication failed. Check GOOGLE_CREDENTIALS and "
            "GOOGLE_PROJECT in cloud-creds.sh."
        )

    # Default: keep command + detail, but trim huge terraform color dumps a bit.
    cleaned = re.sub(r"\x1b\[[0-9;]*m", "", text).strip()
    if cleaned and len(cleaned) > 1200:
        cleaned = (
            cleaned[:1200].rstrip()
            + "\n… (truncated; re-run with -d/--debug for full output)"
        )
    return (
        f"Command failed ({returncode}): {joined}"
        + (f"\n{cleaned}" if cleaned else "")
    )


def _raise_command_failed(result: CommandResult) -> None:
    detail = (result.stderr or result.stdout).strip()
    message = friendly_command_error(
        result.args, returncode=result.returncode, detail=detail
    )
    if is_debug() and detail:
        # Always attach raw output under --debug when we replaced it with a
        # friendlier summary (or when truncated).
        raw = re.sub(r"\x1b\[[0-9;]*m", "", detail).strip()
        if raw and raw not in message:
            message = f"{message}\n\n[debug] raw output:\n{raw}"
            debug_detail(f"command exit {result.returncode}")
    raise VpnNodeBuilderError(message)


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
        _raise_command_failed(result)
    elif is_debug() and result.returncode == 0 and capture:
        out = (result.stdout or result.stderr).strip()
        if out and len(out) <= 200:
            debug_detail(out.splitlines()[0])
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
        _raise_command_failed(result)
    return result
