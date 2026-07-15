"""Terraform init / plan / apply / destroy / taint helpers."""

from __future__ import annotations

import json
import re
import time
from collections.abc import MutableMapping
from pathlib import Path

from rich.console import Console

from vpn_node_builder.cloud.credentials import CloudSession
from vpn_node_builder.terraform.backend import (
    build_backend_config,
    ensure_backend_resources,
)
from vpn_node_builder.terraform.filters import (
    DropPlanOutNoteFilter,
    compose_filters,
)
from vpn_node_builder.terraform.runner import run_terraform, run_terraform_tee

_TAINT_INSTANCE_RE = re.compile(r"@resource_instance_list:\s*(\S*)")
_TAINT_DATA_RE = re.compile(r"@resource_instance_data_list:\s*(\S*)")
console = Console(stderr=False)

_DEFAULT_INSTANCE_RESOURCES: dict[str, list[str]] = {
    "aws": ["module.bootstrap.aws_instance.bastion"],
    "azure": ["module.bootstrap.azurerm_linux_virtual_machine.bastion"],
    "google": ["module.bootstrap.google_compute_instance.bastion"],
}
_DEFAULT_DATA_RESOURCES: dict[str, list[str]] = {
    "aws": ["module.bootstrap.aws_ebs_volume.bastion-data"],
    "azure": ["module.bootstrap.azurerm_managed_disk.bastion-data"],
    "google": ["module.bootstrap.google_compute_disk.bastion-data"],
}


def terraform_init(
    *,
    node_type: str,
    cloud: str,
    region: str | None,
    template_dir: Path,
    work_dir: Path,
    backend: str | None,
    session: CloudSession,
    environ: MutableMapping[str, str],
) -> None:
    _ = cloud
    backend_name = backend or ""
    if backend_name in {"s3", "azurerm", "gcs"}:
        ensure_backend_resources(
            backend_name, region=region, environ=environ, session=session
        )
    config = build_backend_config(
        backend_name,
        node_type=node_type,
        region=region,
        environ=environ,
    )
    args = ["init", "-reconfigure", *config.args] if config.args else ["init"]
    run_terraform(
        args,
        template_dir=template_dir,
        work_dir=work_dir,
        environ=environ,
        capture=False,
    )


def terraform_plan(
    *,
    template_dir: Path,
    work_dir: Path,
    environ: MutableMapping[str, str],
) -> None:
    run_terraform_tee(
        ["plan"],
        template_dir=template_dir,
        work_dir=work_dir,
        environ=environ,
        log_path=work_dir / "plan.log",
        console_filter=compose_filters(DropPlanOutNoteFilter()),
    )


def terraform_apply(
    *,
    template_dir: Path,
    work_dir: Path,
    environ: MutableMapping[str, str],
) -> Path:
    start = time.time()
    apply_log = work_dir / "apply.log"
    # Stream full apply output (including Outputs:). Secrets must be marked
    # ``sensitive = true`` in cookbook / module outputs so Terraform redacts them.
    # Pass console_filter=compose_filters(...) here to filter apply console output.
    run_terraform_tee(
        ["apply", "-auto-approve"],
        template_dir=template_dir,
        work_dir=work_dir,
        environ=environ,
        log_path=apply_log,
        console_filter=compose_filters(),
    )

    output = run_terraform(
        ["output", "-json"],
        template_dir=template_dir,
        work_dir=work_dir,
        environ=environ,
        capture=True,
    )
    output_path = work_dir / "output.json"
    output_path.write_text(output.stdout, encoding="utf-8")
    _write_ssh_keys(output_path, work_dir)

    elapsed = int(time.time() - start)
    minutes, seconds = divmod(elapsed, 60)
    console.print(
        f"[green]Deploy operation completed in {minutes}m and {seconds}s.[/green]"
    )
    return output_path


def _write_ssh_keys(output_path: Path, work_dir: Path) -> None:
    data = json.loads(output_path.read_text(encoding="utf-8"))
    instances = data.get("cb_managed_instances", {}).get("value") or []
    if instances:
        first = instances[0]
        name = str(first.get("name") or "instance")
        ssh_key = first.get("ssh_key")
        if ssh_key:
            key_path = work_dir / f"{name}-ssh-key.pem"
            key_path.write_text(str(ssh_key), encoding="utf-8")
            key_path.chmod(0o600)
    default_entry = data.get("cb_default_ssh_private_key") or data.get(
        "cb_default_openssh_private_key"
    )
    default_key = (default_entry or {}).get("value")
    if default_key and default_key != "null":
        key_path = work_dir / "default-ssh-key.pem"
        key_path.write_text(str(default_key), encoding="utf-8")
        key_path.chmod(0o600)


def terraform_destroy(
    *,
    template_dir: Path,
    work_dir: Path,
    environ: MutableMapping[str, str],
) -> None:
    apply_log = work_dir / "apply.log"
    run_terraform_tee(
        ["destroy", "-auto-approve"],
        template_dir=template_dir,
        work_dir=work_dir,
        environ=environ,
        log_path=apply_log,
        console_filter=compose_filters(),
    )
    output_path = work_dir / "output.json"
    if output_path.exists():
        output_path.unlink()


def _split_resource_list(raw: str) -> list[str]:
    return [part for part in raw.split(",") if part]


def _annotated_resources(
    template_dir: Path,
    cloud: str,
    *,
    annotation_re: re.Pattern[str],
    defaults: dict[str, list[str]],
) -> list[str]:
    input_tpl = template_dir / f"{cloud}-input.tf"
    if input_tpl.is_file():
        text = input_tpl.read_text(encoding="utf-8")
        match = annotation_re.search(text)
        if match is not None:
            return _split_resource_list(match.group(1))
    return list(defaults.get(cloud, []))


def taint_resources_from_input(
    template_dir: Path,
    cloud: str,
    *,
    include_data_store: bool = False,
) -> list[str]:
    """Resources to taint for ``--upgrade`` / ``--rebuild``.

    Reads ``@resource_instance_list`` (VM) and, when ``include_data_store`` is
    true, also ``@resource_instance_data_list`` (persistent data volume).
    """
    resources = _annotated_resources(
        template_dir,
        cloud,
        annotation_re=_TAINT_INSTANCE_RE,
        defaults=_DEFAULT_INSTANCE_RESOURCES,
    )
    if include_data_store:
        resources.extend(
            _annotated_resources(
                template_dir,
                cloud,
                annotation_re=_TAINT_DATA_RE,
                defaults=_DEFAULT_DATA_RESOURCES,
            )
        )
    # Preserve order while dropping duplicates.
    seen: set[str] = set()
    unique: list[str] = []
    for resource in resources:
        if resource in seen:
            continue
        seen.add(resource)
        unique.append(resource)
    return unique


def terraform_taint_bastion(
    *,
    cloud: str,
    template_dir: Path,
    work_dir: Path,
    environ: MutableMapping[str, str],
    include_data_store: bool = False,
) -> None:
    resources = taint_resources_from_input(
        template_dir, cloud, include_data_store=include_data_store
    )
    for resource in resources:
        run_terraform(
            ["taint", resource],
            template_dir=template_dir,
            work_dir=work_dir,
            environ=environ,
            capture=False,
        )
