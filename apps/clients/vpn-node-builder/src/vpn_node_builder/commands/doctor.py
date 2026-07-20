"""Developer/runtime diagnostics command."""

from __future__ import annotations

import os
from pathlib import Path

import typer
from rich.console import Console

from vpn_node_builder.cloud.credentials import CloudSession
from vpn_node_builder.core.bastion import BASTION_IMAGE_ENV, current_bastion_image_name
from vpn_node_builder.core.credentials import REQUIRED_CREDENTIALS
from vpn_node_builder.core.environment import (
    BUILD_VARS_FILENAME,
    CLOUD_CREDS_FILENAME,
    check_tools,
    source_shell_files,
)
from vpn_node_builder.core.eula import is_eula_accepted
from vpn_node_builder.core.paths import (
    COOKBOOK_PATH_ENV,
    PathContext,
    resolve_paths,
    running_in_docker,
)
from vpn_node_builder.core.workspace import (
    WORKSPACE_NAME_ENV,
    deployment_folder,
    deployment_name,
    inspect_template_links,
    iter_deployed_configs,
    list_child_dirs,
    set_working_dir,
)
from vpn_node_builder.terraform.backend import (
    azure_container_name,
    probe_state_storage,
)

console = Console()

_CLOUD_BACKEND = {"aws": "s3", "google": "gcs", "azure": "azurerm"}

# Shared label column for nested ``- key: value`` lines (includes the colon).
# Wide enough for ``VPNB_COOKBOOK_PATH:`` and typical ``node/cloud/region:`` keys.
_LABEL_WIDTH = 24


def _section(title: str) -> None:
    console.print(f"  {title}:", soft_wrap=True)


def _item(label: str, value: object, *, width: int = _LABEL_WIDTH) -> None:
    """Print an aligned ``- label: value`` line under a section."""
    console.print(f"    - {f'{label}:':<{width}} {value}", soft_wrap=True)


def _bullet(text: str) -> None:
    console.print(f"    - {text}", soft_wrap=True)


def _load_soft_environ(cwd: Path) -> dict[str, str]:
    """Merge cloud-creds / build-vars into a copy of os.environ (never raises)."""
    environ = dict(os.environ)
    files = [
        cwd / CLOUD_CREDS_FILENAME,
        cwd / BUILD_VARS_FILENAME,
    ]
    present = [p for p in files if p.is_file()]
    if not present:
        return environ
    try:
        return source_shell_files(present, environ=environ)
    except Exception:  # noqa: BLE001 - doctor stays soft
        return environ


def _configured_clouds(environ: dict[str, str]) -> list[str]:
    configured: list[str] = []
    for cloud, required in REQUIRED_CREDENTIALS.items():
        if all((environ.get(name) or "").strip() for name in required):
            configured.append(cloud)
    return configured


def doctor() -> None:
    """Show resolved paths, cookbook/template health, and soft cloud checks."""
    cwd = Path.cwd()
    in_docker = running_in_docker()
    environ = _load_soft_environ(cwd)
    paths: PathContext = resolve_paths(cwd=cwd, environ=environ)
    workspace = set_working_dir(cwd=cwd, environ=environ)
    folder = deployment_folder(workspace, environ)
    configs = iter_deployed_configs(workspace.workspace_root, environ)
    recipes = list_child_dirs(paths.recipes_root)
    links = inspect_template_links(workspace.template_dir, paths.recipes_root)
    usable_templates = [
        link.name for link in links if link.status == "ok" and link.name in recipes
    ]
    problem_links = [link for link in links if link.status in {"broken", "stale"}]
    hints: list[str] = []

    console.print("[bold]vpn-node-builder doctor[/bold]")

    # --- runtime ---
    _section("runtime")
    if in_docker:
        _item("mode", "Docker container")
        _item(
            "work mount",
            f"{paths.work_mount} (host project directory mounted here)",
        )
        _item("working dir", workspace.working_dir)
        if not (environ.get(WORKSPACE_NAME_ENV) or "").strip():
            hints.append(
                f"Running in Docker without {WORKSPACE_NAME_ENV}; workspace "
                f"name fell back to {folder!r}. Set it in build-vars.sh or "
                "update the brew launcher so host folder names are preserved."
            )
    else:
        _item("mode", "native (host Python)")
        _item("working dir", workspace.working_dir)
        if folder == "work" and workspace.working_dir.name == "work":
            hints.append(
                "Working directory is named 'work'; if this is unexpected, "
                f"set {WORKSPACE_NAME_ENV} explicitly."
            )

    # --- bastion image ---
    image_name = current_bastion_image_name(environ)
    _section("bastion image")
    _item("image pattern", image_name or "(not set)")
    if not image_name:
        hints.append(
            f"{BASTION_IMAGE_ENV} is not set (process env / build-vars.sh). "
            "Deploys need a MyCS node image name or wildcard pattern."
        )

    # --- paths ---
    cookbook_override = (environ.get(COOKBOOK_PATH_ENV) or "").strip()
    _section("paths")
    _item("repo root", paths.repo_root or "(not detected)")
    if cookbook_override:
        _item("cookbook root", f"{paths.cookbook_root} (from {COOKBOOK_PATH_ENV})")
        if in_docker and cookbook_override.startswith(
            ("/Users/", "/home/", "C:\\", "C:/")
        ):
            hints.append(
                f"{COOKBOOK_PATH_ENV} points at a host path that is not visible "
                "inside the container. Unset it (use the image cookbook) or "
                "mount that path into the container."
            )
    elif in_docker:
        _item(
            "cookbook root",
            f"{paths.cookbook_root} (image default)",
        )
    else:
        _item("cookbook root", paths.cookbook_root)
    _item("recipes root", paths.recipes_root)
    _item("recipes readable", "yes" if paths.recipes_root.is_dir() else "NO")
    _item("utils bin", paths.utils_bin or "(not detected)")
    _item("workspace root", workspace.workspace_root)
    _item("template dir", workspace.template_dir)

    # --- control files / eula ---
    _section("control files")
    _item(
        "eula accepted",
        "yes" if is_eula_accepted(workspace.workspace_root) else "no",
    )
    creds = cwd / CLOUD_CREDS_FILENAME
    build_vars = cwd / BUILD_VARS_FILENAME
    _item(
        "cloud-creds.sh",
        f"{'present' if creds.is_file() else 'missing'} ({creds})",
    )
    _item(
        "build-vars.sh",
        f"{'present' if build_vars.is_file() else 'missing'} ({build_vars})",
    )

    # --- workspace name ---
    name_source = (
        WORKSPACE_NAME_ENV
        if (environ.get(WORKSPACE_NAME_ENV) or "").strip()
        else "working dir name"
    )
    _section("workspace")
    _item("name", f"{folder} (from {name_source})")

    # --- cookbooks / templates ---
    _section("cookbooks (node types)")
    if recipes:
        for name in recipes:
            _bullet(name)
    else:
        _bullet("(none — cookbook recipes not found)")
        hints.append(
            f"No recipes under {paths.recipes_root}. Set {COOKBOOK_PATH_ENV} "
            "when running natively, or use the Docker image cookbook."
        )

    _section("template links (.workspace/templates)")
    if not links:
        _bullet("(empty)")
    else:
        for link in links:
            _item(link.name, f"{link.status} — {link.detail}")

    if not usable_templates and recipes:
        hints.append(
            "No usable template links for deploy (broken, stale, or empty). "
            f"Fix with: rm -rf {workspace.template_dir} "
            "then re-run any vpnb command (links are recreated automatically)."
        )
    elif problem_links:
        hints.append(
            "Some template links are broken or stale (common after switching "
            f"between native and Docker). Fix with: rm -rf {workspace.template_dir}"
        )

    # --- derived names ---
    _section("state storage (derived, region-bound)")
    _item("s3 / gcs bucket", f"vpnb-{folder}-<region>")
    _item(
        "azure",
        f"account vpnb{folder}<region>, container {azure_container_name(folder)}",
    )

    _section("vpn vpc names (derived)")
    if configs:
        for node_type, cloud, region in configs:
            location = f"{node_type}/{cloud}" + (f"/{region}" if region else "")
            _item(location, deployment_name(folder, cloud, region))
    else:
        _bullet("(no deployments found under .workspace/run)")

    # --- credentials / tools ---
    configured = _configured_clouds(environ)
    _section("cloud credentials")
    for cloud, required in REQUIRED_CREDENTIALS.items():
        if cloud in configured:
            _item(cloud, "configured")
        else:
            missing = [
                name for name in required if not (environ.get(name) or "").strip()
            ]
            _item(cloud, f"incomplete (missing {', '.join(missing)})")

    _section("tools")
    for status in check_tools(path_env=environ.get("PATH") or os.environ.get("PATH")):
        mark = "ok" if status.present else "MISSING"
        detail = status.path or status.install_url
        _item(status.name, f"{mark} ({detail})")

    # --- state bucket probes ---
    _section("state buckets (probe, no create/delete)")
    session = CloudSession()
    session.bind_environ(environ)
    probe_targets = sorted(
        {
            (cloud, region)
            for _, cloud, region in configs
            if cloud in _CLOUD_BACKEND and region
        }
    )
    if not probe_targets and configured:
        _bullet(
            "(no deployed regions to probe; deploy once or list shows after "
            "output.json exists)"
        )
    elif not probe_targets:
        _bullet("(skipped — no credentials / no deployments)")
    for cloud, region in probe_targets:
        backend = _CLOUD_BACKEND[cloud]
        label = f"{cloud}/{region}"
        if cloud not in configured:
            _item(label, "skipped (credentials incomplete)")
            continue
        status, detail = probe_state_storage(
            backend,
            base_name=folder,
            region=region,
            environ=environ,
            session=session,
        )
        _item(label, f"{status} — {detail}")
        if status == "missing":
            hints.append(
                f"State storage for {label} is missing; the next "
                "`deploy-node … -i` will try to create it."
            )

    # --- hints ---
    if hints:
        _section("hints")
        seen: set[str] = set()
        for hint in hints:
            if hint in seen:
                continue
            seen.add(hint)
            _bullet(hint)

    typer.echo("OK")
