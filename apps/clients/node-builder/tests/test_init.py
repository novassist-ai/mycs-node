from __future__ import annotations

from pathlib import Path

from typer.testing import CliRunner

from node_builder.cli import app
from node_builder.core.environment import BUILD_VARS_FILENAME, CLOUD_CREDS_FILENAME
from node_builder.core.eula import SKIP_EULA_ENV
from node_builder.core.init_files import (
    BUILD_VARS_STUB,
    CLOUD_CREDS_STUB,
    initialize_control_files,
)

runner = CliRunner()


def test_initialize_control_files_creates_stubs(tmp_path: Path) -> None:
    result = initialize_control_files(tmp_path)
    assert CLOUD_CREDS_FILENAME in result.created
    assert BUILD_VARS_FILENAME in result.created
    assert (tmp_path / CLOUD_CREDS_FILENAME).read_text(encoding="utf-8") == CLOUD_CREDS_STUB
    build_vars = (tmp_path / BUILD_VARS_FILENAME).read_text(encoding="utf-8")
    assert build_vars == BUILD_VARS_STUB
    assert 'TF_VAR_company_name="novassist"' in build_vars
    assert 'TF_VAR_organization_name="novassist dev"' in build_vars


def test_initialize_control_files_idempotent(tmp_path: Path) -> None:
    initialize_control_files(tmp_path)
    creds = tmp_path / CLOUD_CREDS_FILENAME
    creds.write_text("export AWS_ACCESS_KEY=keep-me\n", encoding="utf-8")
    result = initialize_control_files(tmp_path)
    assert result.created == ()
    assert set(result.skipped) == {CLOUD_CREDS_FILENAME, BUILD_VARS_FILENAME}
    assert creds.read_text(encoding="utf-8") == "export AWS_ACCESS_KEY=keep-me\n"


def test_nb_init_cli(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv(SKIP_EULA_ENV, "1")
    result = runner.invoke(app, ["init"])
    assert result.exit_code == 0, result.output
    assert (tmp_path / CLOUD_CREDS_FILENAME).is_file()
    assert (tmp_path / BUILD_VARS_FILENAME).is_file()
    assert (tmp_path / ".workspace" / "run").is_dir()
    assert "created" in result.output


def test_nb_init_cli_skips_existing(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv(SKIP_EULA_ENV, "1")
    (tmp_path / CLOUD_CREDS_FILENAME).write_text("export AWS_ACCESS_KEY=x\n", encoding="utf-8")
    (tmp_path / BUILD_VARS_FILENAME).write_text("export TF_VAR_name=y\n", encoding="utf-8")
    result = runner.invoke(app, ["init"])
    assert result.exit_code == 0, result.output
    assert "skipped" in result.output
    assert (tmp_path / CLOUD_CREDS_FILENAME).read_text(encoding="utf-8") == (
        "export AWS_ACCESS_KEY=x\n"
    )
