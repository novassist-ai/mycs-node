"""Terraform init / plan / apply / destroy / taint helpers."""

from __future__ import annotations

import json
import re
import time
from collections.abc import MutableMapping
from pathlib import Path

from node_builder.cloud.credentials import CloudSession
from node_builder.terraform.backend import (
    build_backend_config,
    ensure_backend_resources,
)
from node_builder.terraform.runner import run_terraform

_TAINT_LIST_RE = re.compile(r"@resource_instance_list:\s*(\S+)")


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
    run_terraform(
        ["plan"],
        template_dir=template_dir,
        work_dir=work_dir,
        environ=environ,
        capture=False,
    )


def _filter_outputs_stream(line: str, *, dropping: list[bool]) -> str | None:
    if line.startswith("Outputs:"):
        dropping[0] = True
        return None
    if dropping[0]:
        return None
    return line


def terraform_apply(
    *,
    template_dir: Path,
    work_dir: Path,
    environ: MutableMapping[str, str],
) -> Path:
    start = time.time()
    apply_log = work_dir / "apply.log"
    # Capture apply output, write log, omit Outputs: section from console-parity filter.
    result = run_terraform(
        ["apply", "-auto-approve"],
        template_dir=template_dir,
        work_dir=work_dir,
        environ=environ,
        capture=True,
    )
    dropping = [False]
    filtered_lines: list[str] = []
    for line in result.stdout.splitlines():
        kept = _filter_outputs_stream(line, dropping=dropping)
        if kept is not None:
            filtered_lines.append(kept)
    apply_log.write_text(result.stdout, encoding="utf-8")

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
    _ = elapsed  # callers may log; keep parity hook
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
    default_key = data.get("cb_default_openssh_private_key", {}).get("value")
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
    result = run_terraform(
        ["destroy", "-auto-approve"],
        template_dir=template_dir,
        work_dir=work_dir,
        environ=environ,
        capture=True,
    )
    (work_dir / "apply.log").write_text(result.stdout, encoding="utf-8")
    output_path = work_dir / "output.json"
    if output_path.exists():
        output_path.unlink()


def taint_resources_from_input(template_dir: Path, cloud: str) -> list[str]:
    input_tpl = template_dir / f"{cloud}-input.tf"
    if input_tpl.is_file():
        text = input_tpl.read_text(encoding="utf-8")
        match = _TAINT_LIST_RE.search(text)
        if match:
            return [part for part in match.group(1).split(",") if part]

    defaults = {
        "aws": ["module.bootstrap.aws_instance.bastion"],
        "azure": ["module.bootstrap.azurerm_linux_virtual_machine.bastion"],
        "google": ["module.bootstrap.google_compute_instance.bastion"],
    }
    return list(defaults.get(cloud, []))


def terraform_taint_bastion(
    *,
    cloud: str,
    template_dir: Path,
    work_dir: Path,
    environ: MutableMapping[str, str],
) -> None:
    resources = taint_resources_from_input(template_dir, cloud)
    for resource in resources:
        run_terraform(
            ["taint", resource],
            template_dir=template_dir,
            work_dir=work_dir,
            environ=environ,
            capture=False,
        )
