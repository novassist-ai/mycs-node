from __future__ import annotations

from pathlib import Path

from node_builder.core.paths import COOKBOOK_PATH_ENV, WORK_MOUNT, find_repo_root, resolve_paths


def test_work_mount_constant() -> None:
    assert WORK_MOUNT == Path("/work")


def test_find_repo_root_from_node_builder(tmp_path: Path) -> None:
    # Build a minimal fake repo layout
    recipes = tmp_path / "cloud" / "cookbook" / "recipes"
    recipes.mkdir(parents=True)
    (tmp_path / "apps" / "clients" / "node-builder").mkdir(parents=True)

    assert find_repo_root(tmp_path / "apps" / "clients" / "node-builder") == tmp_path.resolve()


def test_resolve_paths_uses_override(tmp_path: Path) -> None:
    cookbook = tmp_path / "custom-cookbook"
    cookbook.mkdir()
    ctx = resolve_paths(cwd=tmp_path, environ={COOKBOOK_PATH_ENV: str(cookbook)})
    assert ctx.cookbook_root == cookbook.resolve()
    assert ctx.recipes_root == cookbook.resolve() / "recipes"
    assert ctx.work_mount == WORK_MOUNT


def test_resolve_paths_from_repo_layout(tmp_path: Path) -> None:
    recipes = tmp_path / "cloud" / "cookbook" / "recipes"
    recipes.mkdir(parents=True)
    (tmp_path / "apps" / "clients" / "node-builder").mkdir(parents=True)

    ctx = resolve_paths(cwd=tmp_path, environ={})
    assert ctx.repo_root == tmp_path.resolve()
    assert ctx.cookbook_root == (tmp_path / "cloud" / "cookbook").resolve()
    assert ctx.recipes_root == recipes.resolve()
