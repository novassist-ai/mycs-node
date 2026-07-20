"""Bastion image name resolution for doctor and deploy messaging."""

from __future__ import annotations

import os

BASTION_IMAGE_ENV = "TF_VAR_bastion_image_name"


def current_bastion_image_name(environ: dict[str, str] | None = None) -> str | None:
    """Return the effective bastion image name from ``environ`` or the process env."""
    source = environ if environ is not None else os.environ
    name = (source.get(BASTION_IMAGE_ENV) or "").strip()
    return name or None
