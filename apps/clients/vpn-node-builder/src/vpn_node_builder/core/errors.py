"""Domain errors for the vpn-node-builder CLI."""

from __future__ import annotations


class VpnNodeBuilderError(Exception):
    """User-facing error; message is safe to print to the console.

    Optional ``usage`` is printed before the error (bash ``usage::*`` parity).
    When ``soft`` is true the CLI omits the ``ERROR!`` prefix (selection prompts).
    """

    def __init__(
        self,
        message: str,
        *,
        usage: str | None = None,
        soft: bool = False,
    ) -> None:
        super().__init__(message)
        self.usage = usage
        self.soft = soft
