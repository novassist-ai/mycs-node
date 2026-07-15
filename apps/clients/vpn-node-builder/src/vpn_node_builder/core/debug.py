"""Debug / trace helpers (parity with bash ``set -x`` via ``-d/--debug``)."""

from __future__ import annotations

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
