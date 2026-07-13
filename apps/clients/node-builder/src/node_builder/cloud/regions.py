"""List and validate cloud regions."""

from __future__ import annotations

import json
from collections.abc import Mapping, MutableMapping

from node_builder.cloud.credentials import CloudSession
from node_builder.core.errors import NodeBuilderError
from node_builder.core.process import run_cmd
from node_builder.core.workspace import clouds_with_regions


def list_regions(
    cloud: str,
    *,
    session: CloudSession,
    environ: MutableMapping[str, str],
) -> list[str]:
    session.bind_environ(environ)
    if cloud == "aws":
        session.ensure_aws()
        result = run_cmd(
            [
                "aws",
                "ec2",
                "describe-regions",
                "--query",
                "Regions[].RegionName",
                "--output",
                "json",
            ],
            environ=dict(environ),
        )
        regions = json.loads(result.stdout)
        return sorted(str(r) for r in regions)
    if cloud == "azure":
        session.ensure_azure()
        result = run_cmd(
            ["az", "account", "list-locations", "--query", "[].name", "-o", "json"],
            environ=dict(environ),
        )
        regions = json.loads(result.stdout)
        return sorted(str(r) for r in regions)
    if cloud == "google":
        session.ensure_google()
        result = run_cmd(
            ["gcloud", "compute", "regions", "list", "--format=value(name)"],
            environ=dict(environ),
        )
        return sorted(line.strip() for line in result.stdout.splitlines() if line.strip())
    raise NodeBuilderError(f'Cloud "{cloud}" does not use regions.')


def validate_region(
    cloud: str,
    region: str,
    *,
    session: CloudSession,
    environ: MutableMapping[str, str],
) -> None:
    if cloud not in clouds_with_regions(dict(environ)):
        return
    regions = list_regions(cloud, session=session, environ=environ)
    if region not in regions:
        raise NodeBuilderError(f'Unknown {cloud} region "{region}".')


def first_zone_for_region(
    region: str,
    *,
    environ: Mapping[str, str],
) -> str:
    result = run_cmd(
        ["gcloud", "compute", "zones", "list", "--format=json"],
        environ=dict(environ),
    )
    zones = json.loads(result.stdout)
    matched = sorted(
        z["name"]
        for z in zones
        if region in str(z.get("region", ""))
    )
    if not matched:
        raise NodeBuilderError(f'No Google Cloud zones found for region "{region}".')
    return matched[0]
