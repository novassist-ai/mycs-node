"""Stub templates for workspace control files created by ``nb init``."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from node_builder.core.environment import BUILD_VARS_FILENAME, CLOUD_CREDS_FILENAME

CLOUD_CREDS_STUB = """\
# AWS IaaS credentials for Terraform
export AWS_ACCESS_KEY=
export AWS_SECRET_KEY=

# GCP IaaS credentials for Terraform
export GOOGLE_CREDENTIALS=
export GOOGLE_PROJECT=

# Azure IaaS credentials for Terraform
export ARM_USE_MSI=true
export ARM_SUBSCRIPTION_ID=
export ARM_TENANT_ID=
export ARM_CLIENT_ID=
export ARM_CLIENT_SECRET=
"""

BUILD_VARS_STUB = """\
# Deployment identifier or name
export TF_VAR_name=

# DNS Zone for all deployments
export TF_VAR_attach_dns_zone=false

# Uncomment only if attaching to a DNS zone
# - AWS DNS configuration
#export TF_VAR_aws_dns_zone=
# - Azure DNS configuration
#export TF_VAR_azure_dns_zone=
#export TF_VAR_azure_dns_zone_resource_group=
# - Google DNS configuration
#export TF_VAR_google_dns_managed_zone_name=
#export TF_VAR_google_dns_zone=

# Values used for creating self-signed X509 certs
export TF_VAR_company_name="novassist"
export TF_VAR_organization_name="novassist dev"
export TF_VAR_locality="Boston"
export TF_VAR_province="MA"
export TF_VAR_country="US"

export TF_VAR_idle_shutdown_time=60

# One of ipsec/openvpn. For wireguard configuration
# use the MyCS client.
export TF_VAR_vpn_type=ipsec

export TF_VAR_vpn_users="user1|password1,user2|password2"

# Bastion appliance image (public cloud sandbox recipes).
# Docker image `novassist/node-builder` sets TF_VAR_bastion_image_name at build time.
# Override here for native development, e.g.:
#export TF_VAR_bastion_image_name=mycs-node-image_dev
"""


@dataclass(frozen=True)
class InitResult:
    working_dir: Path
    created: tuple[str, ...]
    skipped: tuple[str, ...]


def write_stub_if_missing(path: Path, content: str) -> bool:
    """Write ``content`` when ``path`` does not exist. Returns True if created."""
    if path.exists():
        return False
    path.write_text(content, encoding="utf-8")
    return True


def initialize_control_files(working_dir: Path) -> InitResult:
    """Create ``cloud-creds.sh`` and ``build-vars.sh`` stubs if missing."""
    working_dir.mkdir(parents=True, exist_ok=True)
    created: list[str] = []
    skipped: list[str] = []

    creds = working_dir / CLOUD_CREDS_FILENAME
    if write_stub_if_missing(creds, CLOUD_CREDS_STUB):
        created.append(CLOUD_CREDS_FILENAME)
    else:
        skipped.append(CLOUD_CREDS_FILENAME)

    build_vars = working_dir / BUILD_VARS_FILENAME
    if write_stub_if_missing(build_vars, BUILD_VARS_STUB):
        created.append(BUILD_VARS_FILENAME)
    else:
        skipped.append(BUILD_VARS_FILENAME)

    return InitResult(
        working_dir=working_dir.resolve(),
        created=tuple(created),
        skipped=tuple(skipped),
    )
