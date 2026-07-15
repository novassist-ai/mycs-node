"""Ensure and delete remote/local Terraform backend resources."""

from __future__ import annotations

import json
from collections.abc import MutableMapping
from dataclasses import dataclass

from vpn_node_builder.cloud.credentials import CloudSession, ensure_cloud_cli
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.process import run_cmd


@dataclass(frozen=True)
class BackendConfig:
    backend: str
    args: tuple[str, ...]


def _deployment_name(environ: MutableMapping[str, str]) -> str:
    name = (environ.get("TF_VAR_name") or "").strip()
    if not name:
        raise VpnNodeBuilderError(
            'Deployment name "TF_VAR_name" must be set in build-vars.sh.'
        )
    return name


def state_bucket_name(name: str, region: str) -> str:
    return f"{name}-vpn-tfstate-{region}"


def azure_storage_account_name(region: str) -> str:
    return f"vsstate{region}"


def build_backend_config(
    backend: str,
    *,
    node_type: str,
    region: str | None,
    environ: MutableMapping[str, str],
) -> BackendConfig:
    if backend in {"s3", "azurerm", "gcs"}:
        name = _deployment_name(environ)
        if not region:
            raise VpnNodeBuilderError(f'Region is required for backend "{backend}".')
    else:
        name = (environ.get("TF_VAR_name") or "").strip()

    if backend == "s3":
        bucket = state_bucket_name(name, str(region))
        return BackendConfig(
            backend=backend,
            args=(
                f"-backend-config=key={node_type}",
                f"-backend-config=bucket={bucket}",
            ),
        )
    if backend == "azurerm":
        storage_account = azure_storage_account_name(str(region))
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
        bucket = state_bucket_name(name, str(region))
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
            raise VpnNodeBuilderError(
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
    name = _deployment_name(environ) if backend in {"s3", "azurerm", "gcs"} else ""
    if backend == "s3":
        ensure_cloud_cli("aws", session, environ)
        bucket = state_bucket_name(name, str(region))
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
        storage_account = azure_storage_account_name(str(region))
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
        bucket = state_bucket_name(name, str(region))
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


def delete_backend_resources(
    backend: str,
    *,
    region: str | None,
    environ: MutableMapping[str, str],
    session: CloudSession,
) -> str | None:
    """Delete remote backend storage created by :func:`ensure_backend_resources`.

    Returns a short description of what was deleted, or ``None`` when there is
    nothing to remove (local / unknown backends).

    Notes:
    - **s3 / gcs**: deletes the whole ``{name}-vpn-tfstate-{region}`` bucket
      (force). That bucket is shared by all node types for the same deployment
      name and region.
    - **azurerm**: deletes only the storage container named ``TF_VAR_name``
      (shared storage account / ``default`` resource group are left in place).
    """
    if backend not in {"s3", "azurerm", "gcs"}:
        return None
    if not region:
        raise VpnNodeBuilderError(f'Region is required to delete backend "{backend}".')

    name = _deployment_name(environ)
    env = dict(environ)

    if backend == "s3":
        ensure_cloud_cli("aws", session, environ)
        bucket = state_bucket_name(name, region)
        listed = run_cmd(["aws", "s3", "ls"], environ=env, check=False)
        if bucket not in listed.stdout:
            return None
        run_cmd(
            ["aws", "s3", "rb", f"s3://{bucket}", "--force"],
            environ=env,
        )
        return f"s3://{bucket}"

    if backend == "azurerm":
        ensure_cloud_cli("azure", session, environ)
        storage_account = azure_storage_account_name(region)
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
            environ=env,
            check=False,
        )
        if containers.returncode != 0:
            return None
        container_names = {c.get("name") for c in json.loads(containers.stdout or "[]")}
        if name not in container_names:
            return None
        run_cmd(
            [
                "az",
                "storage",
                "container",
                "delete",
                "--name",
                name,
                "--account-name",
                storage_account,
                "--yes",
                "--output",
                "none",
            ],
            environ=env,
        )
        return f"azurerm container {name!r} in account {storage_account}"

    # gcs
    ensure_cloud_cli("google", session, environ)
    bucket = state_bucket_name(name, region)
    listed = run_cmd(["gsutil", "ls"], environ=env, check=False)
    existing = {
        part
        for line in listed.stdout.splitlines()
        for part in [line.strip().rstrip("/").split("/")[-1]]
        if part
    }
    if bucket not in existing:
        return None
    run_cmd(["gsutil", "-m", "rm", "-r", f"gs://{bucket}"], environ=env)
    return f"gs://{bucket}"
