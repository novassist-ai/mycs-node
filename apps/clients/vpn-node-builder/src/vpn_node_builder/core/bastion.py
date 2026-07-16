"""Bastion image name resolution for help and deploy messaging."""

from __future__ import annotations

import os

BASTION_IMAGE_ENV = "TF_VAR_bastion_image_name"


def current_bastion_image_name() -> str | None:
    """Return the effective bastion image name from the process environment."""
    name = (os.environ.get(BASTION_IMAGE_ENV) or "").strip()
    return name or None


def bastion_help_epilog() -> str:
    """Footer for top-level ``vpnb --help`` describing bastion image defaults."""
    name = current_bastion_image_name()
    current = name if name else "(not set)"
    return f"Deploying first MyCS Node image matching pattern: {current}\n"
