"""Debug / trace helpers (parity with bash ``set -x`` via ``-d/--debug``)."""

from __future__ import annotations

_DEBUG = False


def set_debug(enabled: bool) -> None:
    """Enable or disable command tracing for this process."""
    global _DEBUG
    _DEBUG = bool(enabled)


def is_debug() -> bool:
    return _DEBUG
