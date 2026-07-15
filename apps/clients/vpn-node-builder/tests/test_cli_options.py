from __future__ import annotations

import typer

from vpn_node_builder.core.cli_options import resolve_option
from vpn_node_builder.core.debug import is_debug, set_debug


def test_resolve_option_unwraps_typer_option() -> None:
    sentinel = typer.Option(False, "-d", "--debug")
    assert resolve_option(sentinel, False) is False
    assert resolve_option(True, False) is True
    assert resolve_option(None, "default") is None


def test_set_debug_ignores_truthy_non_true() -> None:
    set_debug(False)
    set_debug(typer.Option(False, "--debug"))  # type: ignore[arg-type]
    assert is_debug() is False
    set_debug(True)
    assert is_debug() is True
    set_debug(False)
