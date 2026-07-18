"""Debug / trace helpers (parity with bash ``set -x`` via ``-d/--debug``)."""

from __future__ import annotations

import sys

_DEBUG = False


def set_debug(enabled: bool) -> None:
    """Enable or disable command tracing for this process.

    Only the literal ``True`` enables tracing so accidental truthy sentinels
    (e.g. unbound Typer ``OptionInfo``) cannot turn debug on.
    """
    global _DEBUG
    _DEBUG = enabled is True


def is_debug() -> bool:
    return _DEBUG


def debug_step(message: str) -> None:
    """Print a labeled process step when ``--debug`` is enabled."""
    if _DEBUG:
        print(f">> {message}", file=sys.stderr, flush=True)


def debug_detail(message: str) -> None:
    """Print secondary debug detail (indented) when ``--debug`` is enabled."""
    if _DEBUG:
        print(f"   {message}", file=sys.stderr, flush=True)
