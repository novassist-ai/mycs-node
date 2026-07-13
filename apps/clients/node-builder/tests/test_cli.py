from __future__ import annotations

from typer.testing import CliRunner

from node_builder.cli import app

runner = CliRunner()


def test_help_exits_zero() -> None:
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "node-builder" in result.stdout.lower() or "nb" in result.stdout.lower()


def test_version() -> None:
    result = runner.invoke(app, ["--version"])
    assert result.exit_code == 0
    assert "nb" in result.stdout
