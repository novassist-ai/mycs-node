"""Domain errors for the vpn-node-builder CLI."""

from __future__ import annotations


class VpnNodeBuilderError(Exception):
    """User-facing error; message is safe to print to the console."""
