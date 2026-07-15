"""Start and stop managed node instances."""

from __future__ import annotations

from collections.abc import MutableMapping

from vpn_node_builder.cloud import CLOUD_VAGRANT_VBOX
from vpn_node_builder.cloud.credentials import CloudSession
from vpn_node_builder.cloud.regions import first_zone_for_region
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.process import run_cmd


def start_node(
    cloud: str,
    region: str,
    node_id: str,
    *,
    session: CloudSession,
    environ: MutableMapping[str, str],
) -> None:
    session.bind_environ(environ)
    if cloud == "aws":
        session.ensure_aws()
        run_cmd(
            [
                "aws",
                "ec2",
                "start-instances",
                "--instance-ids",
                node_id,
                "--region",
                region,
            ],
            environ=dict(environ),
        )
        return
    if cloud == "azure":
        session.ensure_azure()
        run_cmd(["az", "vm", "start", "--ids", node_id], environ=dict(environ))
        return
    if cloud == "google":
        session.ensure_google()
        zone = first_zone_for_region(region, environ=environ)
        run_cmd(
            ["gcloud", "compute", "instances", "start", node_id, f"--zone={zone}"],
            environ=dict(environ),
        )
        return
    if cloud == CLOUD_VAGRANT_VBOX:
        run_cmd(
            ["vboxmanage", "startvm", node_id, "--type", "headless"],
            environ=dict(environ),
        )
        return
    raise VpnNodeBuilderError(f'Cannot start nodes for cloud "{cloud}".')


def stop_node(
    cloud: str,
    region: str,
    node_id: str,
    *,
    session: CloudSession,
    environ: MutableMapping[str, str],
) -> None:
    session.bind_environ(environ)
    if cloud == "aws":
        session.ensure_aws()
        run_cmd(
            [
                "aws",
                "ec2",
                "stop-instances",
                "--instance-ids",
                node_id,
                "--region",
                region,
            ],
            environ=dict(environ),
        )
        return
    if cloud == "azure":
        session.ensure_azure()
        run_cmd(
            ["az", "vm", "stop", "--ids", node_id],
            environ=dict(environ),
            check=False,
        )
        run_cmd(
            ["az", "vm", "deallocate", "--ids", node_id],
            environ=dict(environ),
            check=False,
        )
        return
    if cloud == "google":
        session.ensure_google()
        zone = first_zone_for_region(region, environ=environ)
        run_cmd(
            ["gcloud", "compute", "instances", "stop", node_id, f"--zone={zone}"],
            environ=dict(environ),
        )
        return
    if cloud == CLOUD_VAGRANT_VBOX:
        run_cmd(
            ["vboxmanage", "controlvm", node_id, "poweroff"],
            environ=dict(environ),
        )
        return
    raise VpnNodeBuilderError(f'Cannot stop nodes for cloud "{cloud}".')
