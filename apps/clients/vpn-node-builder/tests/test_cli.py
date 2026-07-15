from __future__ import annotations

from typer.testing import CliRunner

from vpn_node_builder.cli import app

runner = CliRunner()


def test_help_exits_zero() -> None:
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "vpn-node-builder" in result.stdout.lower() or "vpnb" in result.stdout.lower()


def test_version() -> None:
    result = runner.invoke(app, ["--version"])
    assert result.exit_code == 0
    assert "vpnb" in result.stdout
