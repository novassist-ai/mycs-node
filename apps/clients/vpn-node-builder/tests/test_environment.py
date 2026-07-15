from __future__ import annotations

from pathlib import Path

import pytest

from vpn_node_builder.core.credentials import validate_cloud_credentials
from vpn_node_builder.core.environment import (
    parse_shell_exports,
    require_control_files,
    require_tools,
    source_shell_files,
    validate_environment,
)
from vpn_node_builder.core.errors import VpnNodeBuilderError


def test_parse_shell_exports_basic() -> None:
    text = """
# comment
export AWS_ACCESS_KEY=abc
export AWS_SECRET_KEY="secret value"
ARM_TENANT_ID='tenant'
TF_VAR_name=demo
"""
    parsed = parse_shell_exports(text)
    assert parsed["AWS_ACCESS_KEY"] == "abc"
    assert parsed["AWS_SECRET_KEY"] == "secret value"
    assert parsed["ARM_TENANT_ID"] == "tenant"
    assert parsed["TF_VAR_name"] == "demo"


def test_source_shell_files_expands_variables(tmp_path: Path) -> None:
    script = tmp_path / "vars.sh"
    script.write_text(
        'export FOO=bar\nexport TF_VAR_name="${FOO}-demo"\n',
        encoding="utf-8",
    )
    # Static parse keeps the literal expansion text
    assert parse_shell_exports(script.read_text(encoding="utf-8"))[
        "TF_VAR_name"
    ] == "${FOO}-demo"
    # Bash sourcing resolves expansions
    env = source_shell_files([script], environ={"PATH": "/bin:/usr/bin"})
    assert env["FOO"] == "bar"
    assert env["TF_VAR_name"] == "bar-demo"


def test_require_tools_missing(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "vpn_node_builder.core.environment.which",
        lambda name, path_env=None: None,
    )
    with pytest.raises(VpnNodeBuilderError, match="Unable to find"):
        require_tools()


def test_require_control_files(tmp_path: Path) -> None:
    with pytest.raises(VpnNodeBuilderError, match="cloud-creds"):
        require_control_files(tmp_path)
    (tmp_path / "cloud-creds.sh").write_text("export AWS_ACCESS_KEY=a\n", encoding="utf-8")
    with pytest.raises(VpnNodeBuilderError, match="build-vars"):
        require_control_files(tmp_path)
    (tmp_path / "build-vars.sh").write_text("export TF_VAR_name=n\n", encoding="utf-8")
    creds, build_vars = require_control_files(tmp_path)
    assert creds.name == "cloud-creds.sh"
    assert build_vars.name == "build-vars.sh"


def test_validate_environment_loads_files(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(
        "vpn_node_builder.core.environment.which",
        lambda name, path_env=None: f"/bin/{name}",
    )
    (tmp_path / "cloud-creds.sh").write_text(
        "export AWS_ACCESS_KEY=key\nexport AWS_SECRET_KEY=secret\n",
        encoding="utf-8",
    )
    (tmp_path / "build-vars.sh").write_text(
        'export TF_VAR_name="demo"\n',
        encoding="utf-8",
    )
    merged = validate_environment(
        tmp_path,
        environ={"PATH": "/bin"},
        apply_to_environ=False,
    )
    assert merged["AWS_ACCESS_KEY"] == "key"
    assert merged["TF_VAR_name"] == "demo"


def test_validate_cloud_credentials_aws() -> None:
    with pytest.raises(VpnNodeBuilderError, match="AWS_ACCESS_KEY"):
        validate_cloud_credentials("aws", {})
    validate_cloud_credentials(
        "aws",
        {"AWS_ACCESS_KEY": "a", "AWS_SECRET_KEY": "b"},
    )


def test_validate_cloud_credentials_azure_and_google() -> None:
    with pytest.raises(VpnNodeBuilderError, match="ARM_CLIENT_ID"):
        validate_cloud_credentials("azure", {"ARM_CLIENT_ID": "x"})
    validate_cloud_credentials(
        "azure",
        {
            "ARM_CLIENT_ID": "a",
            "ARM_CLIENT_SECRET": "b",
            "ARM_TENANT_ID": "c",
        },
    )
    with pytest.raises(VpnNodeBuilderError, match="GOOGLE_CREDENTIALS"):
        validate_cloud_credentials("google", {"GOOGLE_PROJECT": "p"})
    validate_cloud_credentials(
        "google",
        {"GOOGLE_CREDENTIALS": "{}", "GOOGLE_PROJECT": "p"},
    )
