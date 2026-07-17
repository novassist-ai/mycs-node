"""Workspace discovery, template linking, and recipe validation."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

from vpn_node_builder.cloud import CLOUD_VAGRANT_VBOX
from vpn_node_builder.core.credentials import validate_cloud_credentials
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.paths import resolve_paths

EXT_COOKBOOK_PATH_ENV = "EXT_COOKBOOK_PATH"
DEFAULT_EXT_COOKBOOK_PATH = "/usr/local/lib"

CLOUDS_ENABLED_ENV = "CLOUDS_ENABLED"
CLOUDS_WITH_REGIONS_ENV = "CLOUDS_WITH_REGIONS"
CLOUDS_WITHOUT_REGIONS_ENV = "CLOUDS_WITHOUT_REGIONS"

# Local VirtualBox-via-Vagrant target is ``vagrant-vbox`` (recipe dir name).
DEFAULT_CLOUDS_ENABLED = frozenset(
    {"aws", "azure", "google", CLOUD_VAGRANT_VBOX, "docker"}
)
DEFAULT_CLOUDS_WITH_REGIONS = frozenset({"aws", "azure", "google"})
DEFAULT_CLOUDS_WITHOUT_REGIONS = frozenset({CLOUD_VAGRANT_VBOX, "docker"})

_EXTERNAL_NODE_RE = re.compile(
    r"^(?P<node>[a-zA-Z0-9_]+)(?:@(?P<node_cloud>[a-zA-Z0-9_-]+))?:"
    r"(?P<cookbook>[a-zA-Z0-9_]+):(?P<recipe>[a-zA-Z0-9_]+)$"
)
_BACKEND_RE = re.compile(r'backend\s+"(?P<backend>[^"]+)"')

# Bash CLI placeholders when NODE_TYPE / CLOUD positionals are omitted.
PLACEHOLDER_NODE_TYPE = "<NODE_TYPE>"
PLACEHOLDER_CLOUD = "<CLOUD>"


@dataclass(frozen=True)
class WorkspaceContext:
    """Filesystem locations for an active working directory."""

    working_dir: Path
    workspace_root: Path
    template_dir: Path
    recipes_source: Path


@dataclass(frozen=True)
class ValidatedWorkspace:
    """Result of validating a node_type + cloud against the workspace."""

    workspace: WorkspaceContext
    node_type: str
    cloud: str
    region: str | None
    template_dir: Path
    workspace_dir: Path
    backend: str | None
    input_node: str | None
    input_node_cloud: str | None
    is_external_recipe: bool


def _parse_cloud_set(raw: str | None, default: frozenset[str]) -> frozenset[str]:
    if raw is None or not raw.strip():
        return default
    value = raw.strip()
    if value.startswith("^") and value.endswith("$"):
        # Bash-style regex: ^(a|b|c)$
        inner = value[1:-1]
        if inner.startswith("(") and inner.endswith(")"):
            inner = inner[1:-1]
        return frozenset(part for part in inner.split("|") if part)
    return frozenset(part.strip() for part in value.split(",") if part.strip())


def clouds_enabled(environ: dict[str, str] | None = None) -> frozenset[str]:
    env = environ if environ is not None else dict(os.environ)
    return _parse_cloud_set(env.get(CLOUDS_ENABLED_ENV), DEFAULT_CLOUDS_ENABLED)


def clouds_with_regions(environ: dict[str, str] | None = None) -> frozenset[str]:
    env = environ if environ is not None else dict(os.environ)
    return _parse_cloud_set(
        env.get(CLOUDS_WITH_REGIONS_ENV), DEFAULT_CLOUDS_WITH_REGIONS
    )


def clouds_without_regions(environ: dict[str, str] | None = None) -> frozenset[str]:
    env = environ if environ is not None else dict(os.environ)
    return _parse_cloud_set(
        env.get(CLOUDS_WITHOUT_REGIONS_ENV), DEFAULT_CLOUDS_WITHOUT_REGIONS
    )


def cloud_requires_region(cloud: str, environ: dict[str, str] | None = None) -> bool:
    return cloud in clouds_with_regions(environ)


def list_child_dirs(path: Path) -> list[str]:
    if not path.is_dir():
        return []
    return sorted(entry.name for entry in path.iterdir() if entry.is_dir())


# Overrides the workspace name used for name/state derivation. Set by the Docker
# launcher to the host directory's basename (the in-container working dir is the
# fixed /work mount, so its name cannot be used); may also be set by the user.
WORKSPACE_NAME_ENV = "VPNB_WORKSPACE_NAME"

_WORKSPACE_NAME_RE = re.compile(r"[^a-z0-9]+")


def _sanitize_workspace_name(raw: str) -> str:
    """Slugify to a bucket/DNS-safe token: lowercase, non-alnum -> ``-``, trimmed."""
    return _WORKSPACE_NAME_RE.sub("-", raw.strip().lower()).strip("-")


def deployment_folder(
    workspace: WorkspaceContext,
    environ: dict[str, str] | None = None,
) -> str:
    """Workspace name used to derive ``TF_VAR_name`` and state storage.

    Prefers ``VPNB_WORKSPACE_NAME`` (set by the Docker launcher to the host
    directory basename, or by the user) so containerized runs match native ones;
    otherwise falls back to the working directory name. The result is slugified
    to remain valid for S3/GCS bucket and DNS naming.
    """
    env = environ if environ is not None else dict(os.environ)
    override = (env.get(WORKSPACE_NAME_ENV) or "").strip()
    slug = _sanitize_workspace_name(override) if override else ""
    return slug or _sanitize_workspace_name(workspace.working_dir.name)


def deployment_name(folder: str, cloud: str, region: str | None) -> str:
    """Derive ``TF_VAR_name`` as ``<folder>-<cloud>[-<region>]`` (lowercased).

    Region-less clouds omit the region suffix.
    """
    base = f"{folder}-{cloud}"
    return f"{base}-{region}".lower() if region else base.lower()


def iter_deployed_configs(
    workspace_root: Path,
    environ: dict[str, str] | None = None,
) -> list[tuple[str, str, str | None]]:
    """Return ``(node_type, cloud, region)`` for each deployed run directory.

    A run directory counts as deployed when it holds ``output.json`` or an
    initialized ``.terraform`` directory. Region-less clouds yield ``None``.
    """
    configs: list[tuple[str, str, str | None]] = []
    if not workspace_root.is_dir():
        return configs
    without_regions = clouds_without_regions(environ)

    def _is_deployed(run_dir: Path) -> bool:
        return (run_dir / "output.json").exists() or (run_dir / ".terraform").is_dir()

    for node_dir in sorted(p for p in workspace_root.iterdir() if p.is_dir()):
        for cloud_dir in sorted(p for p in node_dir.iterdir() if p.is_dir()):
            cloud = cloud_dir.name
            if cloud in without_regions:
                if _is_deployed(cloud_dir):
                    configs.append((node_dir.name, cloud, None))
                continue
            for region_dir in sorted(p for p in cloud_dir.iterdir() if p.is_dir()):
                if _is_deployed(region_dir):
                    configs.append((node_dir.name, cloud, region_dir.name))
    return configs


def ensure_template_links(template_dir: Path, recipes_source: Path) -> None:
    """Create ``template_dir`` and symlink each recipe family from the cookbook."""
    template_dir.mkdir(parents=True, exist_ok=True)
    if not recipes_source.is_dir():
        raise VpnNodeBuilderError(
            f"Cookbook recipes directory not found: {recipes_source}"
        )
    for entry in recipes_source.iterdir():
        if not entry.is_dir():
            continue
        target = template_dir / entry.name
        if target.exists() or target.is_symlink():
            continue
        target.symlink_to(entry.resolve(), target_is_directory=True)


def set_working_dir(
    cwd: Path | None = None,
    *,
    recipes_source: Path | None = None,
    environ: dict[str, str] | None = None,
) -> WorkspaceContext:
    """Locate or create ``.workspace`` and prepare template symlinks."""
    start = (cwd or Path.cwd()).resolve()
    working_dir = start
    for candidate in (start, *start.parents):
        if (candidate / ".workspace").exists():
            working_dir = candidate
            break
    else:
        working_dir = start
        (working_dir / ".workspace").mkdir(parents=True, exist_ok=True)

    workspace_root = working_dir / ".workspace" / "run"
    workspace_root.mkdir(parents=True, exist_ok=True)

    if recipes_source is None:
        paths = resolve_paths(cwd=working_dir, environ=environ)
        recipes_source = paths.recipes_root

    template_dir = working_dir / ".workspace" / "templates"
    if not template_dir.exists():
        template_dir.mkdir(parents=True, exist_ok=True)
        # Link recipes when available (in-repo, VPNB_COOKBOOK_PATH, or image path).
        # Init is allowed before the cookbook is resolvable; deploy validates later.
        if recipes_source.is_dir():
            ensure_template_links(template_dir, recipes_source)
    else:
        template_dir.mkdir(parents=True, exist_ok=True)

    return WorkspaceContext(
        working_dir=working_dir,
        workspace_root=workspace_root,
        template_dir=template_dir,
        recipes_source=recipes_source.resolve(),
    )


def read_backend(template_dir: Path) -> str | None:
    cloud_tf = template_dir / "cloud.tf"
    if not cloud_tf.is_file():
        return None
    text = cloud_tf.read_text(encoding="utf-8")
    match = _BACKEND_RE.search(text)
    return match.group("backend") if match else None


def validate_workspace(
    workspace: WorkspaceContext,
    *,
    node_type: str,
    cloud: str,
    region: str | None = None,
    environ: dict[str, str] | None = None,
    usage: str | None = None,
) -> ValidatedWorkspace:
    """Resolve recipe template path and deployment workspace directory.

    ``usage`` is attached to unknown NODE_TYPE / CLOUD errors (bash prints
    ``usage::<command>`` before those listings).
    """
    env = environ if environ is not None else dict(os.environ)
    ext_root = Path(env.get(EXT_COOKBOOK_PATH_ENV, DEFAULT_EXT_COOKBOOK_PATH))

    input_node: str | None = None
    input_node_cloud: str | None = None
    is_external = False
    template_dir = workspace.template_dir

    external = _EXTERNAL_NODE_RE.match(node_type)
    if external:
        is_external = True
        input_node = external.group("node")
        input_node_cloud = external.group("node_cloud") or cloud
        cookbook_name = external.group("cookbook")
        recipe_name = external.group("recipe")

        # Bash always checks .../<input_node>/<input_node_cloud>/<region>.
        expected_input = workspace.workspace_root / input_node / input_node_cloud
        if region:
            expected_input = expected_input / region
        if not expected_input.is_dir():
            raise VpnNodeBuilderError(f"Invalid input node '{input_node}'.")

        template_dir = (
            ext_root / cookbook_name / "cloud" / "recipes" / recipe_name / cloud
        )
        if not template_dir.is_dir():
            raise VpnNodeBuilderError(f"Invalid recipe template path '{template_dir}'.")
    else:
        node_dir = template_dir / node_type
        if not node_dir.exists():
            available = list_child_dirs(template_dir)
            listing = "\n".join(f'- "{name}"' for name in available) or "- (none)"
            if node_type == PLACEHOLDER_NODE_TYPE:
                raise VpnNodeBuilderError(
                    "Please select from the available node types for deployment:\n"
                    f"{listing}",
                    usage=usage,
                    soft=True,
                )
            raise VpnNodeBuilderError(
                f"Unknown node type.\n\nAvailable node types for deployment are:\n"
                f"{listing}",
                usage=usage,
            )
        cloud_dir = node_dir / cloud
        if not cloud_dir.exists():
            available = list_child_dirs(node_dir)
            listing = "\n".join(f'- "{name}"' for name in available) or "- (none)"
            if cloud == PLACEHOLDER_CLOUD:
                raise VpnNodeBuilderError(
                    "Please select from the available cloud targets for deployment:\n"
                    f"{listing}",
                    usage=usage,
                    soft=True,
                )
            raise VpnNodeBuilderError(
                f'Unknown cloud target for node of type "{node_type}".\n\n'
                f"Cloud targets available for deployment are:\n{listing}",
                usage=usage,
            )
        if cloud not in clouds_enabled(env):
            raise VpnNodeBuilderError(
                f'Cloud target "{cloud}" is not supported for public '
                "deployments yet. Support for that cloud will be available "
                "in a future release. If you would still like to deploy to "
                "the cloud specified please contact NovAssist support."
            )
        template_dir = cloud_dir

    validate_cloud_credentials(cloud, env)

    workspace_dir = workspace.workspace_root / node_type / cloud
    workspace_dir.mkdir(parents=True, exist_ok=True)

    return ValidatedWorkspace(
        workspace=workspace,
        node_type=node_type,
        cloud=cloud,
        region=region,
        template_dir=template_dir.resolve(),
        workspace_dir=workspace_dir,
        backend=read_backend(template_dir),
        input_node=input_node,
        input_node_cloud=input_node_cloud,
        is_external_recipe=is_external,
    )
