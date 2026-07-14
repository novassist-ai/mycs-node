"""EULA acceptance gate for a workspace."""

from __future__ import annotations

import os
from collections.abc import Callable
from pathlib import Path

from vpn_node_builder.core.errors import VpnNodeBuilderError

EULA_URL = "https://novassist.ai/legal/"
SKIP_EULA_ENV = "VPNB_SKIP_EULA"
EULA_ACCEPTED_FILENAME = "eula_accepted"

_PROMPT = (
    "\nBefore you can deploy Cloud nodes you need to review and\n"
    "accept the NovAssist Software End User Agreement.\n"
    "The terms of the agreement can be found at the following\n"
    f"link.\n\n{EULA_URL}\n\n"
    'Type "yes" if you agree to the terms or (q)uit: '
)


def eula_accepted_path(workspace_root: Path) -> Path:
    return workspace_root / EULA_ACCEPTED_FILENAME


def is_eula_accepted(workspace_root: Path) -> bool:
    return eula_accepted_path(workspace_root).is_file()


def should_skip_eula(environ: dict[str, str] | None = None) -> bool:
    env = environ if environ is not None else dict(os.environ)
    return env.get(SKIP_EULA_ENV, "").strip().lower() in {"1", "true", "yes"}


def check_eula(
    workspace_root: Path,
    *,
    environ: dict[str, str] | None = None,
    input_func: Callable[[str], str] = input,
    output_func: Callable[[str], None] = print,
) -> None:
    """Ensure the EULA has been accepted for this workspace.

    Set ``VPNB_SKIP_EULA=1`` to skip (tests / CI).
    """
    if should_skip_eula(environ):
        return
    if is_eula_accepted(workspace_root):
        return

    response = input_func(_PROMPT).strip()
    if response in {"q", "Q"} or not response:
        raise VpnNodeBuilderError("EULA was not accepted.")
    if response != "yes":
        raise VpnNodeBuilderError('EULA was not accepted. Type "yes" to accept.')

    output_func(
        "\nThank you. You can proceed to launch, run and manage your "
        "nodes in the cloud now...\n"
    )
    eula_accepted_path(workspace_root).touch()
