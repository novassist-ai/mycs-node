"""Ensure remote/local Terraform backend resources exist."""

from __future__ import annotations

import json
from collections.abc import MutableMapping
from dataclasses import dataclass

from node_builder.cloud.credentials import CloudSession, ensure_cloud_cli
from node_builder.core.errors import NodeBuilderError
from node_builder.core.process import run_cmd


@dataclass(frozen=True)
class BackendConfig:
    backend: str
    args: tuple[str, ...]


def build_backend_config(
    backend: str,
    *,
    node_type: str,
    region: str | None,
    environ: MutableMapping[str, str],
) -> BackendConfig:
    name = (environ.get("TF_VAR_name") or "").strip()
    if backend in {"s3", "azurerm", "gcs"} and not name:
        raise NodeBuilderError(
            'Deployment name "TF_VAR_name" must be set in build-vars.sh.'
        )
    if backend in {"s3", "azurerm", "gcs"} and not region:
        raise NodeBuilderError(f'Region is required for backend "{backend}".')

    if backend == "s3":
        bucket = f"{name}-vs-tfstate-{region}"
        return BackendConfig(
            backend=backend,
            args=(
                f"-backend-config=key={node_type}",
                f"-backend-config=bucket={bucket}",
            ),
        )
    if backend == "azurerm":
        storage_account = f"vsstate{region}"
        return BackendConfig(
            backend=backend,
            args=(
                "-backend-config=resource_group_name=default",
                f"-backend-config=container_name={name}",
                "-backend-config=key=terraform.tfstate",
                f"-backend-config=storage_account_name={storage_account}",
            ),
        )
    if backend == "gcs":
        bucket = f"{name}-vs-tfstate-{region}"
        return BackendConfig(
            backend=backend,
            args=(
                f"-backend-config=prefix={node_type}",
                f"-backend-config=bucket={bucket}",
            ),
        )
    if backend == "local":
        local_path = (environ.get("TF_VAR_cb_local_state_path") or "").strip()
        if not local_path:
            raise NodeBuilderError(
                'Local backend requires "TF_VAR_cb_local_state_path".'
            )
        return BackendConfig(
            backend=backend,
            args=(
                f"-backend-config=path={local_path}/terraform/local.tfstate",
            ),
        )
    return BackendConfig(backend=backend, args=())


def ensure_backend_resources(
    backend: str,
    *,
    region: str | None,
    environ: MutableMapping[str, str],
    session: CloudSession,
) -> None:
    name = (environ.get("TF_VAR_name") or "").strip()
    if backend == "s3":
        ensure_cloud_cli("aws", session, environ)
        bucket = f"{name}-vs-tfstate-{region}"
        listed = run_cmd(["aws", "s3", "ls"], environ=dict(environ), check=False)
        if bucket not in listed.stdout:
            run_cmd(
                ["aws", "s3", "mb", f"s3://{bucket}", "--region", str(region)],
                environ=dict(environ),
            )
        return

    if backend == "azurerm":
        ensure_cloud_cli("azure", session, environ)
        groups = run_cmd(
            ["az", "group", "list", "-o", "json"],
            environ=dict(environ),
        )
        names = {g.get("name") for g in json.loads(groups.stdout)}
        if "default" not in names:
            run_cmd(
                [
                    "az",
                    "group",
                    "create",
                    "--name",
                    "default",
                    "--location",
                    str(region),
                    "--output",
                    "none",
                ],
                environ=dict(environ),
            )
        storage_account = f"vsstate{region}"
        accounts = run_cmd(
            ["az", "storage", "account", "list", "-o", "json"],
            environ=dict(environ),
        )
        account_names = {a.get("name") for a in json.loads(accounts.stdout)}
        if storage_account not in account_names:
            run_cmd(
                [
                    "az",
                    "storage",
                    "account",
                    "create",
                    "--name",
                    storage_account,
                    "--location",
                    str(region),
                    "--resource-group",
                    "default",
                    "--sku",
                    "Standard_LRS",
                    "--output",
                    "none",
                ],
                environ=dict(environ),
            )
        containers = run_cmd(
            [
                "az",
                "storage",
                "container",
                "list",
                "--account-name",
                storage_account,
                "-o",
                "json",
            ],
            environ=dict(environ),
        )
        container_names = {c.get("name") for c in json.loads(containers.stdout)}
        if name not in container_names:
            run_cmd(
                [
                    "az",
                    "storage",
                    "container",
                    "create",
                    "--name",
                    name,
                    "--account-name",
                    storage_account,
                    "--output",
                    "none",
                ],
                environ=dict(environ),
            )
        return

    if backend == "gcs":
        ensure_cloud_cli("google", session, environ)
        bucket = f"{name}-vs-tfstate-{region}"
        listed = run_cmd(["gsutil", "ls"], environ=dict(environ), check=False)
        existing = {
            part
            for line in listed.stdout.splitlines()
            for part in [line.strip().rstrip("/").split("/")[-1]]
            if part
        }
        if bucket not in existing:
            run_cmd(
                ["gsutil", "mb", "-l", str(region), f"gs://{bucket}"],
                environ=dict(environ),
            )
        return
