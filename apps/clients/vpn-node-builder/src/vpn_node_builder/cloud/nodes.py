"""Discover deployed nodes from workspace output.json files."""

from __future__ import annotations

import json
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from pathlib import Path

from vpn_node_builder.cloud import CLOUD_VAGRANT_VBOX
from vpn_node_builder.cloud.credentials import CloudSession
from vpn_node_builder.cloud.regions import first_zone_for_region
from vpn_node_builder.core.process import run_cmd
from vpn_node_builder.core.workspace import clouds_without_regions


@dataclass(frozen=True)
class NodeRecord:
    node_type: str
    cloud: str
    region: str
    address: str
    state: str
    version: str
    root_user: str
    root_passwd: str
    managed_instance_id: str
    vpn_type: str
    instance_ip: str
    output_path: Path


def _json_get(data: dict, *path: str, default: str = "") -> str:
    cur: object = data
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    if cur is None or cur == "null":
        return default
    return str(cur)


def iter_output_files(workspace_root: Path) -> Iterator[Path]:
    if not workspace_root.is_dir():
        return
    yield from workspace_root.rglob("output.json")


def parse_node_from_output(
    output_path: Path,
    *,
    workspace_root: Path,
    environ: dict[str, str] | None = None,
) -> NodeRecord:
    data = json.loads(output_path.read_text(encoding="utf-8"))
    instances = data.get("cb_managed_instances", {}).get("value") or []
    first = instances[0] if instances else {}

    managed_id = str(first.get("id") or "")
    address = str(first.get("fqdn") or "")
    if not address:
        address = str(first.get("public_ip") or "")
    if not address:
        private_ip = str(first.get("private_ip") or "")
        address = f"{private_ip}[private]" if private_ip else ""

    version_raw = _json_get(data, "cb_node_version", "value").strip()
    # Terraform already emits the trailing segment of bastion_image_name
    # (e.g. "0.2.0-dev1"). Older outputs may still be "prefix_1.2.3".
    if "_" in version_raw:
        version = version_raw.rsplit("_", 1)[-1]
    else:
        version = version_raw
    vpn_type = _json_get(data, "cb_vpn_type", "value")
    instance_ip = str(first.get("public_ip") or first.get("private_ip") or "")

    region_path = output_path.parent
    region = region_path.name
    without_regions = clouds_without_regions(environ)
    if region in without_regions:
        cloud_path = region_path
        region = ""
    else:
        cloud_path = region_path.parent
    cloud = cloud_path.name
    node_type = cloud_path.parent.name

    return NodeRecord(
        node_type=node_type,
        cloud=cloud,
        region=region,
        address=address,
        state="unknown",
        version=version,
        root_user=str(first.get("root_user") or ""),
        root_passwd=str(first.get("root_passwd") or ""),
        managed_instance_id=managed_id,
        vpn_type=vpn_type,
        instance_ip=instance_ip,
        output_path=output_path,
    )


def get_node_state(
    cloud: str,
    region: str,
    managed_instance_id: str,
    *,
    session: CloudSession,
    environ: dict[str, str],
) -> str:
    session.bind_environ(environ)
    state = ""
    try:
        if cloud == "aws":
            session.ensure_aws()
            result = run_cmd(
                [
                    "aws",
                    "ec2",
                    "describe-instances",
                    "--instance-ids",
                    managed_instance_id,
                    "--region",
                    region,
                    "--output",
                    "json",
                ],
                environ=dict(environ),
                check=False,
            )
            if result.returncode == 0:
                payload = json.loads(result.stdout)
                state = (
                    payload["Reservations"][0]["Instances"][0]["State"]["Name"]
                )
        elif cloud == "azure":
            session.ensure_azure()
            result = run_cmd(
                ["az", "vm", "show", "--id", managed_instance_id, "--show-details", "-o", "json"],
                environ=dict(environ),
                check=False,
            )
            if result.returncode == 0:
                payload = json.loads(result.stdout)
                azure_state = str(payload.get("powerState") or "")
                if azure_state == "VM running":
                    state = "running"
                elif azure_state in {"VM stopped", "VM deallocated"}:
                    state = "stopped"
                else:
                    state = azure_state.split(" ", 1)[-1] if azure_state else ""
        elif cloud == "google":
            session.ensure_google()
            zone = first_zone_for_region(region, environ=environ)
            result = run_cmd(
                [
                    "gcloud",
                    "compute",
                    "instances",
                    "describe",
                    managed_instance_id,
                    "--zone",
                    zone,
                    "--format=json",
                ],
                environ=dict(environ),
                check=False,
            )
            if result.returncode == 0:
                payload = json.loads(result.stdout)
                gcp_state = str(payload.get("status") or "").lower()
                if gcp_state == "running":
                    state = "running"
                elif gcp_state == "terminated":
                    state = "stopped"
                else:
                    state = gcp_state
        elif cloud == CLOUD_VAGRANT_VBOX:
            result = run_cmd(
                ["vboxmanage", "showvminfo", managed_instance_id],
                environ=dict(environ),
                check=False,
            )
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    if line.startswith("State:"):
                        raw = line.split(":", 1)[1].strip().split()[0]
                        if raw in {"powered", "saved"}:
                            state = "stopped"
                        else:
                            state = raw
                        break
    except Exception:
        state = ""
    return state or "unknown"


def list_nodes(
    workspace_root: Path,
    *,
    session: CloudSession,
    environ: dict[str, str],
    state_fn: Callable[..., str] | None = None,
) -> list[NodeRecord]:
    resolver = state_fn or get_node_state
    nodes: list[NodeRecord] = []
    for output_path in sorted(iter_output_files(workspace_root)):
        record = parse_node_from_output(
            output_path, workspace_root=workspace_root, environ=environ
        )
        state = resolver(
            record.cloud,
            record.region,
            record.managed_instance_id,
            session=session,
            environ=environ,
        )
        nodes.append(
            NodeRecord(
                **{**record.__dict__, "state": state},
            )
        )
    return nodes
