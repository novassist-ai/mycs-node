from __future__ import annotations

from typer.testing import CliRunner

from vpn_node_builder.cli import app
from vpn_node_builder.core.bastion import current_bastion_image_name


def test_current_bastion_image_name_reads_environ_dict() -> None:
    assert (
        current_bastion_image_name({"TF_VAR_bastion_image_name": "mycs-node-image_dev"})
        == "mycs-node-image_dev"
    )
    assert current_bastion_image_name({}) is None


def test_top_level_help_omits_bastion_image(monkeypatch) -> None:
    monkeypatch.setenv("TF_VAR_bastion_image_name", "mycs-node-image_0.1.0-dev2")
    result = CliRunner().invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "mycs-node-image_0.1.0-dev2" not in result.stdout
    assert "Deploying first MyCS Node image matching pattern" not in result.stdout
    assert "image pattern" not in result.stdout


def test_doctor_shows_bastion_image_pattern(tmp_path, monkeypatch) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("TF_VAR_bastion_image_name", "mycs-node-image_*.*.*-dev.*")
    monkeypatch.setenv("VPNB_SKIP_EULA", "1")
    result = CliRunner().invoke(app, ["doctor"])
    assert result.exit_code == 0
    assert "bastion image" in result.stdout
    assert "image pattern" in result.stdout
    assert "mycs-node-image_*.*.*-dev.*" in result.stdout
