from __future__ import annotations

import pytest
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


def test_version_prefers_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("version", "0.6.0-dev1")
    result = runner.invoke(app, ["--version"])
    assert result.exit_code == 0
    assert "vpnb 0.6.0-dev1" in result.stdout
