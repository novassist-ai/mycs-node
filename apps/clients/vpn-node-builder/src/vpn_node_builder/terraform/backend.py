"""Ensure and delete remote/local Terraform backend resources.

Buckets / storage accounts are region-bound, so state storage is scoped per
``(cloud, region)`` and named from ``<folder>`` + ``<region>`` (see
:func:`state_bucket_name`). Node types within the same region coexist in that
bucket via the state key ``<node_type>`` (:func:`state_key`).
"""

from __future__ import annotations

import json
import re
from collections.abc import MutableMapping
from dataclasses import dataclass
from pathlib import Path

from vpn_node_builder.cloud.credentials import CloudSession, ensure_cloud_cli
from vpn_node_builder.core.debug import debug_detail, debug_step
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.process import run_cmd


@dataclass(frozen=True)
class BackendConfig:
    backend: str
    args: tuple[str, ...]


def _require_base_name(base_name: str) -> str:
    name = (base_name or "").strip().lower()
    if not name:
        raise VpnNodeBuilderError("Workspace folder name could not be determined.")
    return name


def state_bucket_name(base_name: str, region: str | None) -> str:
    """s3 / gcs bucket name: ``vpnb-<folder>-<region>`` (``vpnb-<folder>`` if no region).

    Buckets are region-bound, so the region is part of the name.
    """
    base = f"vpnb-{_require_base_name(base_name)}"
    return f"{base}-{region.lower()}" if region else base


def azure_container_name(base_name: str) -> str:
    """Azure blob container name ``vpnb-<folder>`` (region lives in the account)."""
    return f"vpnb-{_require_base_name(base_name)}"


def azure_storage_account_name(base_name: str, region: str | None) -> str:
    """Azure storage account ``vpnb<folder><region>`` (lowercase alnum, <=24)."""
    base = re.sub(r"[^a-z0-9]", "", _require_base_name(base_name))
    region_part = re.sub(r"[^a-z0-9]", "", (region or "").lower())
    return f"vpnb{base}{region_part}"[:24]


def state_key(node_type: str) -> str:
    """Terraform state key/prefix ``<node_type>`` (region is encoded in the bucket)."""
    return node_type


def build_backend_config(
    backend: str,
    *,
    node_type: str,
    region: str | None,
    base_name: str,
    environ: MutableMapping[str, str],
) -> BackendConfig:
    if backend in {"s3", "azurerm", "gcs"} and not region:
        raise VpnNodeBuilderError(f'Region is required for backend "{backend}".')

    key = state_key(node_type)

    if backend == "s3":
        bucket = state_bucket_name(base_name, region)
        return BackendConfig(
            backend=backend,
            args=(
                f"-backend-config=key={key}",
                f"-backend-config=bucket={bucket}",
            ),
        )
    if backend == "azurerm":
        storage_account = azure_storage_account_name(base_name, region)
        container = azure_container_name(base_name)
        return BackendConfig(
            backend=backend,
            args=(
                "-backend-config=resource_group_name=default",
                f"-backend-config=container_name={container}",
                f"-backend-config=key={key}",
                f"-backend-config=storage_account_name={storage_account}",
            ),
        )
    if backend == "gcs":
        bucket = state_bucket_name(base_name, region)
        return BackendConfig(
            backend=backend,
            args=(
                f"-backend-config=prefix={key}",
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
    base_name: str,
    environ: MutableMapping[str, str],
    session: CloudSession,
) -> None:
    """Create the per-(cloud, region) bucket / account+container if it does not exist."""
    if backend == "s3":
        ensure_cloud_cli("aws", session, environ)
        bucket = state_bucket_name(base_name, region)
        debug_step(f"ensure S3 state bucket s3://{bucket} (region={region})")
        listed = run_cmd(["aws", "s3", "ls"], environ=dict(environ), check=False)
        if bucket not in listed.stdout:
            debug_detail(f"creating bucket s3://{bucket}")
            run_cmd(
                ["aws", "s3", "mb", f"s3://{bucket}", "--region", str(region)],
                environ=dict(environ),
            )
        else:
            debug_detail(f"bucket already present: s3://{bucket}")
        return

    if backend == "azurerm":
        ensure_cloud_cli("azure", session, environ)
        debug_step(
            "ensure Azure state account "
            f"{azure_storage_account_name(base_name, region)} (region={region})"
        )
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
        storage_account = azure_storage_account_name(base_name, region)
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
        container = azure_container_name(base_name)
        container_names = {c.get("name") for c in json.loads(containers.stdout)}
        if container not in container_names:
            run_cmd(
                [
                    "az",
                    "storage",
                    "container",
                    "create",
                    "--name",
                    container,
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
        bucket = state_bucket_name(base_name, region)
        debug_step(f"ensure GCS state bucket gs://{bucket} (region={region})")
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


def probe_state_storage(
    backend: str,
    *,
    base_name: str,
    region: str | None,
    environ: MutableMapping[str, str],
    session: CloudSession,
) -> tuple[str, str]:
    """Soft-check whether remote state storage exists (never creates/deletes).

    Returns ``(status, detail)`` where status is one of:
    ``exists``, ``missing``, ``skipped``, ``error``.
    """
    if backend not in {"s3", "azurerm", "gcs"}:
        return "skipped", f"backend {backend!r} has no remote state bucket"
    if not region:
        return "skipped", "region required for remote state probe"

    env = dict(environ)
    try:
        if backend == "s3":
            ensure_cloud_cli("aws", session, environ)
            bucket = state_bucket_name(base_name, region)
            listed = run_cmd(["aws", "s3", "ls"], environ=env, check=False)
            if listed.returncode != 0:
                return "error", (listed.stderr or listed.stdout or "aws s3 ls failed").strip()
            if bucket in listed.stdout:
                return "exists", f"s3://{bucket}"
            return "missing", f"s3://{bucket} (can be created on next deploy -i)"

        if backend == "azurerm":
            ensure_cloud_cli("azure", session, environ)
            account = azure_storage_account_name(base_name, region)
            accounts = run_cmd(
                ["az", "storage", "account", "list", "-o", "json"],
                environ=env,
                check=False,
            )
            if accounts.returncode != 0:
                return "error", (accounts.stderr or accounts.stdout or "az list failed").strip()
            names = {a.get("name") for a in json.loads(accounts.stdout or "[]")}
            container = azure_container_name(base_name)
            if account in names:
                return "exists", f"account {account}, container {container}"
            return "missing", (
                f"account {account} (can be created on next deploy -i)"
            )

        # gcs
        ensure_cloud_cli("google", session, environ)
        bucket = state_bucket_name(base_name, region)
        listed = run_cmd(["gsutil", "ls"], environ=env, check=False)
        if listed.returncode != 0:
            return "error", (listed.stderr or listed.stdout or "gsutil ls failed").strip()
        existing = {
            part
            for line in listed.stdout.splitlines()
            for part in [line.strip().rstrip("/").split("/")[-1]]
            if part
        }
        if bucket in existing:
            return "exists", f"gs://{bucket}"
        return "missing", f"gs://{bucket} (can be created on next deploy -i)"
    except VpnNodeBuilderError as exc:
        return "error", str(exc)
    except Exception as exc:  # noqa: BLE001 - doctor must never crash on probes
        return "error", str(exc)


def delete_backend_resources(
    backend: str,
    *,
    base_name: str,
    region: str | None,
    environ: MutableMapping[str, str],
    session: CloudSession,
) -> str | None:
    """Delete the ``(cloud, region)`` state storage, if it exists.

    Returns a short description of what was deleted, or ``None`` when there is
    nothing to remove (local / unknown backends, or storage not present).

    Notes:
    - **s3 / gcs**: deletes the ``vpnb-<folder>-<region>`` bucket (force). That
      bucket holds every node type deployed to that region.
    - **azurerm**: deletes the ``vpnb<folder><region>`` storage account (the
      per-region "bucket"); the ``default`` resource group is left in place.
    """
    if backend not in {"s3", "azurerm", "gcs"}:
        return None

    env = dict(environ)

    if backend == "s3":
        ensure_cloud_cli("aws", session, environ)
        bucket = state_bucket_name(base_name, region)
        debug_step(f"delete S3 state bucket s3://{bucket}")
        listed = run_cmd(["aws", "s3", "ls"], environ=env, check=False)
        if bucket not in listed.stdout:
            debug_detail("bucket not found; nothing to delete")
            return None
        run_cmd(
            ["aws", "s3", "rb", f"s3://{bucket}", "--force"],
            environ=env,
        )
        return f"s3://{bucket}"

    if backend == "azurerm":
        ensure_cloud_cli("azure", session, environ)
        storage_account = azure_storage_account_name(base_name, region)
        debug_step(f"delete Azure state account {storage_account}")
        accounts = run_cmd(
            ["az", "storage", "account", "list", "-o", "json"],
            environ=env,
            check=False,
        )
        if accounts.returncode != 0:
            return None
        account_names = {a.get("name") for a in json.loads(accounts.stdout or "[]")}
        if storage_account not in account_names:
            return None
        run_cmd(
            [
                "az",
                "storage",
                "account",
                "delete",
                "--name",
                storage_account,
                "--resource-group",
                "default",
                "--yes",
                "--output",
                "none",
            ],
            environ=env,
        )
        return f"azurerm storage account {storage_account!r}"

    # gcs
    ensure_cloud_cli("google", session, environ)
    bucket = state_bucket_name(base_name, region)
    debug_step(f"delete GCS state bucket gs://{bucket}")
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


def read_cached_backend(run_dir: Path) -> tuple[str, dict] | None:
    """Return ``(backend_type, config)`` cached in ``run_dir/.terraform``.

    Returns ``None`` when no initialized backend is recorded.
    """
    state_file = run_dir / ".terraform" / "terraform.tfstate"
    if not state_file.is_file():
        return None
    try:
        data = json.loads(state_file.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None
    backend = data.get("backend") or {}
    backend_type = backend.get("type")
    if not backend_type:
        return None
    return str(backend_type), dict(backend.get("config") or {})


def backend_state_exists(
    run_dir: Path,
    *,
    environ: MutableMapping[str, str],
    session: CloudSession,
) -> bool | None:
    """Check whether the remote state storage a deployment was initialized with
    still exists, using the backend cached in ``run_dir/.terraform``.

    Returns ``True`` when the storage is present, ``False`` when the cloud
    definitively reports it absent, and ``None`` when it cannot be determined
    (no cached backend, local backend, or a failed/ambiguous lookup) — in which
    case callers should fall back to a normal destroy.
    """
    cached = read_cached_backend(run_dir)
    if cached is None:
        return None
    backend_type, config = cached
    env = dict(environ)

    if backend_type == "s3":
        bucket = config.get("bucket")
        if not bucket:
            return None
        ensure_cloud_cli("aws", session, environ)
        listed = run_cmd(["aws", "s3", "ls"], environ=env, check=False)
        if listed.returncode != 0:
            return None
        return bucket in listed.stdout

    if backend_type == "gcs":
        bucket = config.get("bucket")
        if not bucket:
            return None
        ensure_cloud_cli("google", session, environ)
        listed = run_cmd(["gsutil", "ls"], environ=env, check=False)
        if listed.returncode != 0:
            return None
        existing = {
            part
            for line in listed.stdout.splitlines()
            for part in [line.strip().rstrip("/").split("/")[-1]]
            if part
        }
        return bucket in existing

    if backend_type == "azurerm":
        account = config.get("storage_account_name")
        if not account:
            return None
        ensure_cloud_cli("azure", session, environ)
        accounts = run_cmd(
            ["az", "storage", "account", "list", "-o", "json"],
            environ=env,
            check=False,
        )
        if accounts.returncode != 0:
            return None
        names = {a.get("name") for a in json.loads(accounts.stdout or "[]")}
        return account in names

    return None
