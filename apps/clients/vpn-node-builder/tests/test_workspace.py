from __future__ import annotations

from pathlib import Path

import pytest

from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.workspace import (
    ensure_template_links,
    set_working_dir,
    validate_workspace,
)


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
