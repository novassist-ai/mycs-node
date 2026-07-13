"""Set and validate deployment region for Terraform."""

from __future__ import annotations

from collections.abc import MutableMapping

from node_builder.cloud.credentials import CloudSession, ensure_cloud_cli
from node_builder.cloud.regions import validate_region
from node_builder.core.errors import NodeBuilderError
from node_builder.core.workspace import clouds_with_regions


def set_cloud_region(
    cloud: str,
    region: str | None,
    *,
    backend: str | None,
    session: CloudSession,
    environ: MutableMapping[str, str],
) -> None:
    """Validate region (when required) and align backend provider credentials."""
    if cloud in clouds_with_regions(dict(environ)):
        if not region:
            raise NodeBuilderError(f'Region is required for cloud "{cloud}".')
        validate_region(cloud, region, session=session, environ=environ)
        if cloud == "aws":
            environ["AWS_DEFAULT_REGION"] = region
        environ["TF_VAR_region"] = region
    elif region:
        environ["TF_VAR_region"] = region

    backend_cloud = {
        "s3": "aws",
        "azurerm": "azure",
        "gcs": "google",
    }.get(backend or "")
    if backend_cloud:
        ensure_cloud_cli(backend_cloud, session, environ)
