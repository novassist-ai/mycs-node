from __future__ import annotations

from pathlib import Path

import pytest

from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.workspace import (
    deployment_folder,
    deployment_name,
    ensure_template_links,
    iter_deployed_configs,
    set_working_dir,
    validate_workspace,
)


def test_deployment_name_with_and_without_region() -> None:
    assert deployment_name("MyProj", "aws", "us-east-1") == "myproj-aws-us-east-1"
    assert deployment_name("MyProj", "vagrant-vbox", None) == "myproj-vagrant-vbox"


def test_deployment_folder_prefers_env_override_and_sanitizes() -> None:
    from types import SimpleNamespace

    workspace = SimpleNamespace(working_dir=Path("/work"))
    # Docker case: /work dir name overridden by the launcher-provided host name.
    assert (
        deployment_folder(workspace, {"VPNB_WORKSPACE_NAME": "My Project_1"})
        == "my-project-1"
    )
    # No override -> falls back to the working directory name.
    assert deployment_folder(workspace, {}) == "work"


def test_iter_deployed_configs(tmp_path: Path) -> None:
    root = tmp_path / "run"
    aws = root / "sandbox" / "aws" / "us-east-1"
    aws.mkdir(parents=True)
    (aws / "output.json").write_text("{}", encoding="utf-8")
    # region-less cloud: deployed marker directly under the cloud dir
    local = root / "sandbox" / "vagrant-vbox"
    (local / ".terraform").mkdir(parents=True)
    # not deployed (no marker) -> excluded
    (root / "sandbox" / "google" / "europe-west1").mkdir(parents=True)

    configs = iter_deployed_configs(root, {})
    assert ("sandbox", "aws", "us-east-1") in configs
    assert ("sandbox", "vagrant-vbox", None) in configs
    assert ("sandbox", "google", "europe-west1") not in configs


def _make_recipes(root: Path) -> Path:
    recipes = root / "cloud" / "cookbook" / "recipes"
    sandbox_aws = recipes / "sandbox" / "aws"
    sandbox_aws.mkdir(parents=True)
    (sandbox_aws / "cloud.tf").write_text(
        'terraform {\n  backend "s3" {}\n}\n',
        encoding="utf-8",
    )
    (recipes / "sandbox" / "vagrant-vbox").mkdir(parents=True)
    (recipes / "sandbox" / "vagrant-vbox" / "cloud.tf").write_text(
        'terraform {\n  backend "local" {}\n}\n',
        encoding="utf-8",
    )
    return recipes


def test_set_working_dir_creates_workspace_and_templates(tmp_path: Path) -> None:
    recipes = _make_recipes(tmp_path)
    work = tmp_path / "project"
    work.mkdir()
    ctx = set_working_dir(cwd=work, recipes_source=recipes)
    assert ctx.working_dir == work.resolve()
    assert ctx.workspace_root.is_dir()
    assert (ctx.template_dir / "sandbox").is_symlink()
    assert (ctx.template_dir / "sandbox" / "aws").is_dir()


def test_set_working_dir_discovers_ancestor(tmp_path: Path) -> None:
    recipes = _make_recipes(tmp_path)
    root = tmp_path / "project"
    nested = root / "a" / "b"
    nested.mkdir(parents=True)
    (root / ".workspace").mkdir()
    ctx = set_working_dir(cwd=nested, recipes_source=recipes)
    assert ctx.working_dir == root.resolve()


def test_ensure_template_links_idempotent(tmp_path: Path) -> None:
    recipes = _make_recipes(tmp_path)
    template_dir = tmp_path / "templates"
    ensure_template_links(template_dir, recipes)
    ensure_template_links(template_dir, recipes)
    assert (template_dir / "sandbox").is_symlink()
    assert (template_dir / "sandbox").resolve() == (recipes / "sandbox").resolve()


def test_ensure_template_links_refreshes_stale_and_broken(tmp_path: Path) -> None:
    recipes = _make_recipes(tmp_path)
    other = _make_recipes(tmp_path / "other")
    template_dir = tmp_path / "templates"
    template_dir.mkdir()
    # Broken Docker-era link.
    (template_dir / "sandbox").symlink_to(
        Path("/usr/local/lib/vpn-node-builder/cloud/cookbook/recipes/sandbox"),
        target_is_directory=True,
    )
    ensure_template_links(template_dir, other)
    assert (template_dir / "sandbox").resolve() == (other / "sandbox").resolve()
    # Stale link pointing at a different cookbook is refreshed on the next call.
    ensure_template_links(template_dir, recipes)
    assert (template_dir / "sandbox").resolve() == (recipes / "sandbox").resolve()


def test_validate_workspace_happy_path(tmp_path: Path) -> None:
    recipes = _make_recipes(tmp_path)
    work = tmp_path / "project"
    work.mkdir()
    ws = set_working_dir(cwd=work, recipes_source=recipes)
    validated = validate_workspace(
        ws,
        node_type="sandbox",
        cloud="aws",
        environ={
            "AWS_ACCESS_KEY": "a",
            "AWS_SECRET_KEY": "b",
        },
    )
    assert validated.backend == "s3"
    assert validated.template_dir == (recipes / "sandbox" / "aws").resolve()
    assert validated.workspace_dir.is_dir()
    assert not validated.is_external_recipe


def test_validate_workspace_unknown_node(tmp_path: Path) -> None:
    recipes = _make_recipes(tmp_path)
    work = tmp_path / "project"
    work.mkdir()
    ws = set_working_dir(cwd=work, recipes_source=recipes)
    with pytest.raises(VpnNodeBuilderError, match="Unknown node type"):
        validate_workspace(ws, node_type="nope", cloud="aws", environ={})


def test_validate_workspace_placeholder_node_lists_types(tmp_path: Path) -> None:
    from vpn_node_builder.core.workspace import PLACEHOLDER_NODE_TYPE

    recipes = _make_recipes(tmp_path)
    work = tmp_path / "project"
    work.mkdir()
    ws = set_working_dir(cwd=work, recipes_source=recipes)
    with pytest.raises(
        VpnNodeBuilderError, match="Please select from the available node types"
    ) as exc:
        validate_workspace(
            ws,
            node_type=PLACEHOLDER_NODE_TYPE,
            cloud="aws",
            environ={},
            usage="USAGE: vpnb deploy-node …",
        )
    assert "sandbox" in str(exc.value)
    assert exc.value.usage == "USAGE: vpnb deploy-node …"
    assert exc.value.soft is True


def test_validate_workspace_unsupported_cloud_mentions_support(
    tmp_path: Path,
) -> None:
    recipes = _make_recipes(tmp_path)
    # Add a cloud recipe dir that is not in CLOUDS_ENABLED.
    oci = recipes / "sandbox" / "oci"
    oci.mkdir(parents=True)
    (oci / "cloud.tf").write_text('backend "local" {}\n', encoding="utf-8")
    work = tmp_path / "project"
    work.mkdir()
    ws = set_working_dir(cwd=work, recipes_source=recipes)
    with pytest.raises(VpnNodeBuilderError, match="NovAssist support"):
        validate_workspace(
            ws,
            node_type="sandbox",
            cloud="oci",
            environ={"CLOUDS_ENABLED": "^(aws|azure|google)$"},
        )


def test_validate_workspace_unknown_cloud(tmp_path: Path) -> None:
    recipes = _make_recipes(tmp_path)
    work = tmp_path / "project"
    work.mkdir()
    ws = set_working_dir(cwd=work, recipes_source=recipes)
    with pytest.raises(VpnNodeBuilderError, match="Unknown cloud target"):
        validate_workspace(ws, node_type="sandbox", cloud="nope", environ={})


def test_validate_workspace_external_recipe(tmp_path: Path) -> None:
    recipes = _make_recipes(tmp_path)
    work = tmp_path / "project"
    work.mkdir()
    ws = set_working_dir(cwd=work, recipes_source=recipes)

    ext = tmp_path / "ext"
    recipe = ext / "mycookbook" / "cloud" / "recipes" / "edge" / "aws"
    recipe.mkdir(parents=True)
    (recipe / "cloud.tf").write_text('backend "s3" {}\n', encoding="utf-8")

    prior = ws.workspace_root / "sandbox" / "aws" / "us-east-1"
    prior.mkdir(parents=True)

    validated = validate_workspace(
        ws,
        node_type="sandbox@aws:mycookbook:edge",
        cloud="aws",
        region="us-east-1",
        environ={
            "EXT_COOKBOOK_PATH": str(ext),
            "AWS_ACCESS_KEY": "a",
            "AWS_SECRET_KEY": "b",
        },
    )
    assert validated.is_external_recipe
    assert validated.input_node == "sandbox"
    assert validated.input_node_cloud == "aws"
    assert validated.template_dir == recipe.resolve()
