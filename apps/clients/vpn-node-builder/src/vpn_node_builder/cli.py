"""Typer application entrypoint for the ``vpnb`` CLI."""

from __future__ import annotations

import typer

from vpn_node_builder import __version__
from vpn_node_builder.commands import register_commands

app = typer.Typer(
    name="vpnb",
    help=(
        "Manage personal cloud VPN nodes across multiple cloud regions. "
        "Use a subcommand such as init, show-regions, deploy-node, or show-nodes."
    ),
    no_args_is_help=True,
    add_completion=False,
)


def _version_callback(value: bool) -> None:
    if value:
        typer.echo(f"vpnb {__version__}")
        raise typer.Exit()


@app.callback()
def main(
    version: bool = typer.Option(
        False,
        "--version",
        "-V",
        help="Show version and exit.",
        callback=_version_callback,
        is_eager=True,
    ),
) -> None:
    """vpn-node-builder CLI root callback."""


register_commands(app)


def run() -> None:
    """Console-script entrypoint."""
    app()


if __name__ == "__main__":
    run()
