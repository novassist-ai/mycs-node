from __future__ import annotations

import os

from typer.testing import CliRunner

from vpn_node_builder.cli import app
from vpn_node_builder.core.bastion import bastion_help_epilog


def test_bastion_help_epilog_includes_image_and_override(monkeypatch) -> None:
    monkeypatch.setenv("TF_VAR_bastion_image_name", "mycs-node-image_0.0.0")
    text = bastion_help_epilog()
    assert "Deploying first MyCS Node image matching pattern: mycs-node-image_0.0.0" in text
    assert "build-vars.sh" not in text
    assert "export TF_VAR_bastion_image_name=" not in text


def test_bastion_help_epilog_when_unset(monkeypatch) -> None:
    monkeypatch.delenv("TF_VAR_bastion_image_name", raising=False)
    text = bastion_help_epilog()
    assert "Deploying first MyCS Node image matching pattern: (not set)" in text


def test_top_level_help_shows_bastion_epilog(monkeypatch) -> None:
    monkeypatch.setenv("TF_VAR_bastion_image_name", "mycs-node-image_0.1.0-dev2")
    app.info.epilog = bastion_help_epilog()

    result = CliRunner().invoke(app, ["--help"])
    assert result.exit_code == 0
    assert (
        "Deploying first MyCS Node image matching pattern: mycs-node-image_0.1.0-dev2"
        in result.stdout
    )
    assert "build-vars.sh" not in result.stdout
