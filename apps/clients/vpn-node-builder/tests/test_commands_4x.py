from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from vpn_node_builder.cli import app
from vpn_node_builder.cloud import CLOUD_VAGRANT_VBOX
from vpn_node_builder.commands._context import prepare_command_context, resolve_deployment
from vpn_node_builder.commands.start_tunnel import TUNNEL_TYPES
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.eula import SKIP_EULA_ENV
from vpn_node_builder.core.workspace import set_working_dir

runner = CliRunner()


def _project_with_recipes(tmp_path: Path) -> Path:
    recipes = tmp_path / "cloud" / "cookbook" / "recipes"
    aws = recipes / "sandbox" / "aws"
    aws.mkdir(parents=True)
    (aws / "cloud.tf").write_text('terraform {\n  backend "s3" {}\n}\n', encoding="utf-8")
    local = recipes / "sandbox" / CLOUD_VAGRANT_VBOX
    local.mkdir(parents=True)
    (local / "cloud.tf").write_text(
        'terraform {\n  backend "local" {}\n}\n', encoding="utf-8"
    )
    (tmp_path / "apps" / "clients" / "vpn-node-builder").mkdir(parents=True)
    work = tmp_path / "project"
    work.mkdir()
    (work / "cloud-creds.sh").write_text(
        "export AWS_ACCESS_KEY=a\nexport AWS_SECRET_KEY=b\n",
        encoding="utf-8",
    )
    (work / "build-vars.sh").write_text('export TF_VAR_name="demo"\n', encoding="utf-8")
    return work


def test_cli_lists_all_commands() -> None:
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    for name in (
        "init",
        "show-regions",
        "deploy-node",
        "destroy-node",
        "destroy-all",
        "reinit-node",
        "download-vpn-config",
        "start-tunnel",
        "show-nodes",
        "doctor",
    ):
        assert name in result.output


def test_resolve_deployment_requires_region(tmp_path: Path, monkeypatch) -> None:
    work = _project_with_recipes(tmp_path)
    monkeypatch.chdir(work)
    monkeypatch.setenv(SKIP_EULA_ENV, "1")
    monkeypatch.setenv("VPNB_COOKBOOK_PATH", str(tmp_path / "cloud" / "cookbook"))
    monkeypatch.setattr(
        "vpn_node_builder.commands._context.validate_environment",
        lambda *a, **k: {
            "AWS_ACCESS_KEY": "a",
            "AWS_SECRET_KEY": "b",
            "TF_VAR_name": "demo",
        },
    )
    ctx = prepare_command_context(require_tools=False)
    ctx.environ.update(
        {
            "AWS_ACCESS_KEY": "a",
            "AWS_SECRET_KEY": "b",
            "TF_VAR_name": "demo",
        }
    )
    # Force cookbook templates
    ctx.workspace = set_working_dir(
        cwd=work, recipes_source=tmp_path / "cloud" / "cookbook" / "recipes"
    )
    monkeypatch.setattr(
        "vpn_node_builder.commands._context.list_regions",
        lambda *a, **k: ["us-east-1", "us-west-2"],
        raising=False,
    )
    monkeypatch.setattr(
        "vpn_node_builder.cloud.regions.list_regions",
        lambda *a, **k: ["us-east-1", "us-west-2"],
    )
    with pytest.raises(VpnNodeBuilderError, match="Please provide a cloud region") as exc:
        resolve_deployment(ctx, node_type="sandbox", cloud="aws", region=None)
    assert exc.value.soft is True

    validated, run_dir = resolve_deployment(
        ctx, node_type="sandbox", cloud="aws", region="us-east-1"
    )
    assert run_dir == validated.workspace_dir / "us-east-1"

    validated, run_dir = resolve_deployment(
        ctx, node_type="sandbox", cloud=CLOUD_VAGRANT_VBOX, region=None
    )
    assert run_dir == validated.workspace_dir


def test_destroy_deployment_inits_before_destroy(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from vpn_node_builder.commands import destroy_node as dn
    from vpn_node_builder.commands._context import CommandContext
    from vpn_node_builder.core.workspace import ValidatedWorkspace

    work = _project_with_recipes(tmp_path)
    monkeypatch.chdir(work)
    monkeypatch.setenv(SKIP_EULA_ENV, "1")
    monkeypatch.setenv("VPNB_COOKBOOK_PATH", str(tmp_path / "cloud" / "cookbook"))

    ws = set_working_dir(cwd=work)
    run_dir = ws.workspace_root / "sandbox" / "aws" / "us-east-1"
    run_dir.mkdir(parents=True)
    (run_dir / "output.json").write_text("{}", encoding="utf-8")

    validated = ValidatedWorkspace(
        workspace=ws,
        node_type="sandbox",
        cloud="aws",
        region="us-east-1",
        template_dir=ws.template_dir / "sandbox" / "aws",
        workspace_dir=ws.workspace_root / "sandbox" / "aws",
        backend="s3",
        input_node=None,
        input_node_cloud=None,
        is_external_recipe=False,
    )

    calls: list[str] = []

    monkeypatch.setattr(
        dn,
        "resolve_deployment",
        lambda *a, **k: (validated, run_dir),
    )
    monkeypatch.setattr(dn, "require_run_dir", lambda *a, **k: None)
    monkeypatch.setattr(dn, "load_input_vars", lambda *a, **k: None)
    monkeypatch.setattr(dn, "set_cloud_region", lambda *a, **k: None)
    monkeypatch.setattr(dn, "backend_state_exists", lambda *a, **k: True)
    monkeypatch.setattr(
        dn,
        "terraform_init",
        lambda **k: calls.append("init"),
    )
    monkeypatch.setattr(
        dn,
        "terraform_destroy",
        lambda **k: calls.append("destroy"),
    )

    ctx = CommandContext(workspace=ws, environ={}, session=object())
    status = dn.destroy_deployment(
        ctx, node_type="sandbox", cloud="aws", region="us-east-1"
    )
    assert status == dn.DESTROYED
    assert calls == ["init", "destroy"]


def test_destroy_all_flow(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    from vpn_node_builder.commands import destroy_all as da

    work = tmp_path / "MyProj"
    root = work / ".workspace" / "run"
    root.mkdir(parents=True)

    class _Workspace:
        working_dir = work
        workspace_root = root

    class _Ctx:
        workspace = _Workspace()
        environ = {"AWS_ACCESS_KEY": "a", "AWS_SECRET_KEY": "b"}
        session = object()

    monkeypatch.setattr(da, "prepare_command_context", lambda *a, **k: _Ctx())
    monkeypatch.setattr(
        da, "iter_deployed_configs", lambda *a, **k: [("sandbox", "aws", "us-east-1")]
    )
    destroyed: list[tuple[str, str, str | None]] = []
    monkeypatch.setattr(
        da,
        "destroy_deployment",
        lambda c, *, node_type, cloud, region: destroyed.append(
            (node_type, cloud, region)
        ),
    )
    deleted: list[tuple[str, str, str | None]] = []

    def fake_delete(backend, *, base_name, region, environ, session):
        deleted.append((backend, base_name, region))
        return f"s3://vpnb-{base_name}-{region}"

    monkeypatch.setattr(da, "delete_backend_resources", fake_delete)

    result = runner.invoke(app, ["destroy-all", "-y"], env={SKIP_EULA_ENV: "1"})
    assert result.exit_code == 0, result.output
    assert destroyed == [("sandbox", "aws", "us-east-1")]
    assert deleted == [("s3", "myproj", "us-east-1")]


def test_destroy_all_skips_missing_state(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from vpn_node_builder.commands import destroy_all as da

    work = tmp_path / "proj"
    root = work / ".workspace" / "run"
    root.mkdir(parents=True)

    class _Workspace:
        working_dir = work
        workspace_root = root

    class _Ctx:
        workspace = _Workspace()
        environ = {"AWS_ACCESS_KEY": "a", "AWS_SECRET_KEY": "b"}
        session = object()

    monkeypatch.setattr(da, "prepare_command_context", lambda *a, **k: _Ctx())
    monkeypatch.setattr(
        da,
        "iter_deployed_configs",
        lambda *a, **k: [
            ("sandbox", "aws", "us-east-1"),
            ("sandbox", "aws", "eu-central-1"),
        ],
    )

    def fake_destroy(c, *, node_type, cloud, region):
        return da.MISSING_STATE if region == "eu-central-1" else "destroyed"

    monkeypatch.setattr(da, "destroy_deployment", fake_destroy)
    deleted: list[tuple[str, str, str | None]] = []
    monkeypatch.setattr(
        da,
        "delete_backend_resources",
        lambda backend, *, base_name, region, environ, session: (
            deleted.append((backend, base_name, region)) or f"s3://x-{region}"
        ),
    )

    result = runner.invoke(app, ["destroy-all", "-y"], env={SKIP_EULA_ENV: "1"})
    assert result.exit_code == 0, result.output
    # Missing-state node is not a failure; both regions' buckets still cleaned.
    assert deleted == [("s3", "proj", "eu-central-1"), ("s3", "proj", "us-east-1")]


def test_start_tunnel_rejects_bad_type() -> None:
    result = runner.invoke(
        app,
        [
            "start-tunnel",
            "sandbox",
            "aws",
            "-r",
            "us-east-1",
            "-t",
            "nope",
        ],
        env={SKIP_EULA_ENV: "1"},
    )
    assert result.exit_code != 0
    assert "Invalid tunnel type" in result.output or "ERROR" in result.output


def test_tunnel_types_complete() -> None:
    assert "udp_over_tcp" in TUNNEL_TYPES
    assert len(TUNNEL_TYPES) == 5


def test_deploy_node_help() -> None:
    result = runner.invoke(app, ["deploy-node", "--help"])
    assert result.exit_code == 0
    assert "--region" in result.output
    assert "--upgrade" in result.output
    assert "--rebuild" in result.output
    assert "-b" in result.output


def test_deploy_node_lists_types_when_args_omitted(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    work = _project_with_recipes(tmp_path)
    monkeypatch.chdir(work)
    monkeypatch.setenv(SKIP_EULA_ENV, "1")
    monkeypatch.setenv("VPNB_COOKBOOK_PATH", str(tmp_path / "cloud" / "cookbook"))
    monkeypatch.setattr(
        "vpn_node_builder.commands._context.validate_environment",
        lambda *a, **k: {
            "AWS_ACCESS_KEY": "a",
            "AWS_SECRET_KEY": "b",
            "TF_VAR_name": "demo",
        },
    )
    set_working_dir(
        cwd=work, recipes_source=tmp_path / "cloud" / "cookbook" / "recipes"
    )
    result = runner.invoke(app, ["deploy-node"])
    assert result.exit_code != 0
    assert "USAGE: vpnb deploy-node" in result.output
    assert "Please select from the available node types" in result.output
    assert "Unknown node type" not in result.output
    assert "ERROR!" not in result.output
    assert "sandbox" in result.output


def test_deploy_node_lists_clouds_when_cloud_omitted(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    work = _project_with_recipes(tmp_path)
    monkeypatch.chdir(work)
    monkeypatch.setenv(SKIP_EULA_ENV, "1")
    monkeypatch.setenv("VPNB_COOKBOOK_PATH", str(tmp_path / "cloud" / "cookbook"))
    monkeypatch.setattr(
        "vpn_node_builder.commands._context.validate_environment",
        lambda *a, **k: {
            "AWS_ACCESS_KEY": "a",
            "AWS_SECRET_KEY": "b",
            "TF_VAR_name": "demo",
        },
    )
    set_working_dir(
        cwd=work, recipes_source=tmp_path / "cloud" / "cookbook" / "recipes"
    )
    result = runner.invoke(app, ["deploy-node", "sandbox"])
    assert result.exit_code != 0
    assert "Please select from the available cloud targets" in result.output
    assert "Unknown cloud target" not in result.output
    assert "ERROR!" not in result.output
    assert "aws" in result.output
