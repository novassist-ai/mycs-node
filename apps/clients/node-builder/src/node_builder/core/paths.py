"""Path resolution for cookbook templates, workspace, and Go utilities."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

# Container workdir mount used by the Docker-hosted CLI (Task 0.1 contract).
WORK_MOUNT = Path("/work")

# Environment override for cookbook location (dev + image).
COOKBOOK_PATH_ENV = "NB_COOKBOOK_PATH"


@dataclass(frozen=True)
class PathContext:
    """Resolved filesystem locations used by the CLI."""

    repo_root: Path | None
    cookbook_root: Path
    recipes_root: Path
    work_mount: Path
    utils_bin: Path | None


def find_repo_root(start: Path | None = None) -> Path | None:
    """Walk parents looking for the mycs-node repository root."""
    current = (start or Path.cwd()).resolve()
    for candidate in (current, *current.parents):
        if (candidate / "cloud" / "cookbook" / "recipes").is_dir() and (
            candidate / "apps" / "clients" / "node-builder"
        ).is_dir():
            return candidate
    return None


def resolve_paths(
    *,
    cwd: Path | None = None,
    environ: dict[str, str] | None = None,
) -> PathContext:
    """Resolve cookbook and utility paths for native-dev or container runs."""
    env = environ if environ is not None else dict(os.environ)
    repo_root = find_repo_root(cwd)

    override = env.get(COOKBOOK_PATH_ENV)
    if override:
        cookbook_root = Path(override).expanduser().resolve()
    elif repo_root is not None:
        cookbook_root = repo_root / "cloud" / "cookbook"
    elif Path("/usr/local/lib/node-builder/cloud/cookbook").is_dir():
        cookbook_root = Path("/usr/local/lib/node-builder/cloud/cookbook")
    else:
        # Fallback keeps the CLI importable before cookbook is present.
        cookbook_root = (repo_root or Path.cwd()) / "cloud" / "cookbook"

    utils_bin: Path | None = None
    if repo_root is not None:
        candidate = repo_root / ".build" / "bin"
        if candidate.exists():
            utils_bin = candidate

    return PathContext(
        repo_root=repo_root,
        cookbook_root=cookbook_root,
        recipes_root=cookbook_root / "recipes",
        work_mount=WORK_MOUNT,
        utils_bin=utils_bin,
    )
