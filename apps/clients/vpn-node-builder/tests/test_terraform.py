from __future__ import annotations

import json
from pathlib import Path

import pytest

from vpn_node_builder.cloud.credentials import CloudSession
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.process import CommandResult
from vpn_node_builder.terraform.backend import build_backend_config, ensure_backend_resources
from vpn_node_builder.terraform.lifecycle import (
    taint_resources_from_input,
    terraform_apply,
    terraform_init,
)
from vpn_node_builder.terraform.region import set_cloud_region


def test_build_backend_config_s3() -> None:
    env = {"TF_VAR_name": "demo"}
    cfg = build_backend_config(
        "s3", node_type="sandbox", region="us-east-1", environ=env
    )
    assert "bucket=demo-vpn-tfstate-us-east-1" in cfg.args[1]


def test_build_backend_config_local() -> None:
    env = {"TF_VAR_cb_local_state_path": "/tmp/state"}
    cfg = build_backend_config(
        "local", node_type="sandbox", region=None, environ=env
    )
    assert cfg.args[0].endswith("/terraform/local.tfstate")


def test_build_backend_config_requires_name() -> None:
    with pytest.raises(VpnNodeBuilderError, match="TF_VAR_name"):
        build_backend_config("s3", node_type="sandbox", region="us-east-1", environ={})


def test_ensure_backend_creates_s3_bucket(monkeypatch) -> None:
    calls: list[tuple[str, ...]] = []

    def fake_run(args, **kwargs):
        calls.append(tuple(args))
        if args[:2] == ("aws", "s3") and args[2] == "ls":
            return CommandResult(args=tuple(args), returncode=0, stdout="", stderr="")
        return CommandResult(args=tuple(args), returncode=0, stdout="", stderr="")

    monkeypatch.setattr("vpn_node_builder.terraform.backend.run_cmd", fake_run)
    env = {
        "TF_VAR_name": "demo",
        "AWS_ACCESS_KEY": "a",
        "AWS_SECRET_KEY": "b",
    }
    session = CloudSession()
    session.bind_environ(env)
    ensure_backend_resources("s3", region="us-east-1", environ=env, session=session)
    assert any(c[:3] == ("aws", "s3", "mb") for c in calls)


def test_set_cloud_region_aws(monkeypatch) -> None:
    monkeypatch.setattr(
        "vpn_node_builder.terraform.region.validate_region",
        lambda *a, **k: None,
    )
    env: dict[str, str] = {
        "AWS_ACCESS_KEY": "a",
        "AWS_SECRET_KEY": "b",
    }
    session = CloudSession()
    session.bind_environ(env)
    set_cloud_region(
        "aws",
        "us-east-1",
        backend="s3",
        session=session,
        environ=env,
    )
    assert env["TF_VAR_region"] == "us-east-1"
    assert env["AWS_DEFAULT_REGION"] == "us-east-1"
    assert env["AWS_ACCESS_KEY_ID"] == "a"


def test_taint_resources_from_input(tmp_path: Path) -> None:
    (tmp_path / "aws-input.tf").write_text(
        "# @resource_instance_list: module.bootstrap.aws_instance.bastion,other.x\n",
        encoding="utf-8",
    )
    assert taint_resources_from_input(tmp_path, "aws") == [
        "module.bootstrap.aws_instance.bastion",
        "other.x",
    ]
    assert taint_resources_from_input(tmp_path, "google") == [
        "module.bootstrap.google_compute_instance.bastion"
    ]


def test_terraform_init_passes_backend_args(monkeypatch, tmp_path: Path) -> None:
    seen: dict[str, object] = {}

    def fake_ensure(*args, **kwargs):
        seen["ensured"] = True

    def fake_run_tf(args, **kwargs):
        seen["args"] = list(args)
        return CommandResult(args=tuple(args), returncode=0, stdout="", stderr="")

    monkeypatch.setattr(
        "vpn_node_builder.terraform.lifecycle.ensure_backend_resources", fake_ensure
    )
    monkeypatch.setattr("vpn_node_builder.terraform.lifecycle.run_terraform", fake_run_tf)
    env = {"TF_VAR_name": "demo", "AWS_ACCESS_KEY": "a", "AWS_SECRET_KEY": "b"}
    terraform_init(
        node_type="sandbox",
        cloud="aws",
        region="us-east-1",
        template_dir=tmp_path,
        work_dir=tmp_path / "run",
        backend="s3",
        session=CloudSession(),
        environ=env,
    )
    assert seen["ensured"] is True
    assert seen["args"][:2] == ["init", "-reconfigure"]


def test_terraform_apply_writes_output_and_keys(monkeypatch, tmp_path: Path) -> None:
    template = tmp_path / "tpl"
    work = tmp_path / "work"
    template.mkdir()
    work.mkdir()
    printed: list[str] = []

    def fake_tee(args, **kwargs):
        assert args[0] == "apply"
        assert "console_filter" in kwargs
        log_path: Path = kwargs["log_path"]
        log_path.write_text(
            "Applying...\nOutputs:\ncb_node_version = \"1.0\"\n",
            encoding="utf-8",
        )
        printed.append("streamed")
        return CommandResult(
            args=tuple(args),
            returncode=0,
            stdout="Applying...\nOutputs:\ncb_node_version = \"1.0\"\n",
            stderr="",
        )

    def fake_run_tf(args, **kwargs):
        if args[0] == "output":
            payload = {
                "cb_managed_instances": {
                    "value": [{"name": "node1", "ssh_key": "PRIVATE"}]
                },
                "cb_default_ssh_private_key": {"value": "DEFAULT"},
            }
            return CommandResult(
                args=tuple(args),
                returncode=0,
                stdout=json.dumps(payload),
                stderr="",
            )
        raise AssertionError(args)

    monkeypatch.setattr(
        "vpn_node_builder.terraform.lifecycle.run_terraform_tee", fake_tee
    )
    monkeypatch.setattr(
        "vpn_node_builder.terraform.lifecycle.run_terraform", fake_run_tf
    )
    output = terraform_apply(template_dir=template, work_dir=work, environ={})
    assert output.is_file()
    assert (work / "apply.log").is_file()
    assert printed == ["streamed"]
    key = work / "node1-ssh-key.pem"
    assert key.read_text(encoding="utf-8") == "PRIVATE"
    assert oct(key.stat().st_mode & 0o777) == "0o600"
    assert (work / "default-ssh-key.pem").read_text(encoding="utf-8") == "DEFAULT"
