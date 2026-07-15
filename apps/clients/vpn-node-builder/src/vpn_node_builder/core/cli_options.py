"""Helpers for invoking Typer command functions outside Click/Typer."""

from __future__ import annotations

from typing import Any, TypeVar

try:
    from typer.models import ArgumentInfo, OptionInfo
except ImportError:  # pragma: no cover
    OptionInfo = type("OptionInfo", (), {})  # type: ignore[misc, assignment]
    ArgumentInfo = type("ArgumentInfo", (), {})  # type: ignore[misc, assignment]

T = TypeVar("T")


def resolve_option(value: Any, default: T) -> T:
    """Return ``default`` when ``value`` is still a Typer Option/Argument sentinel.

    Direct Python calls into Typer-decorated functions (e.g. from ``show-nodes``)
    do not go through Click parameter binding, so omitted kwargs keep their
    ``typer.Option(...)`` / ``typer.Argument(...)`` objects — which are truthy
    and would incorrectly enable flags like ``debug`` / ``clean`` / ``show``.
    """
    if isinstance(value, (OptionInfo, ArgumentInfo)):
        return default
    return value  # type: ignore[return-value]
