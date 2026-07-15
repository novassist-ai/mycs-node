"""Load and validate cloud credential variables."""

from __future__ import annotations

from vpn_node_builder.core.errors import VpnNodeBuilderError

REQUIRED_CREDENTIALS: dict[str, tuple[str, ...]] = {
    "aws": ("AWS_ACCESS_KEY", "AWS_SECRET_KEY"),
    "azure": ("ARM_CLIENT_ID", "ARM_CLIENT_SECRET", "ARM_TENANT_ID"),
    "google": ("GOOGLE_CREDENTIALS", "GOOGLE_PROJECT"),
}


def validate_cloud_credentials(cloud: str, environ: dict[str, str]) -> None:
    """Raise if required credential env vars are missing for ``cloud``."""
    required = REQUIRED_CREDENTIALS.get(cloud)
    if not required:
        return

    missing = [name for name in required if not (environ.get(name) or "").strip()]
    if missing:
        joined = ", ".join(f'"{name}"' for name in required)
        raise VpnNodeBuilderError(
            f"The environment variables {joined} must be set in the "
            f'"cloud-creds.sh" file for cloud "{cloud}".'
        )
