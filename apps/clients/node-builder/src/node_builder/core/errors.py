"""Domain errors for the node-builder CLI."""

from __future__ import annotations


class NodeBuilderError(Exception):
    """User-facing error; message is safe to print to the console."""
