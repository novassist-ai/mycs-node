"""Typer application entrypoint for the ``nb`` CLI."""

from __future__ import annotations

import typer

from node_builder import __version__
from node_builder.commands import register_commands

app = typer.Typer(
    name="nb",
    help="MyCS node-builder — deploy and manage VPN node environments.",
    no_args_is_help=True,
    add_completion=False,
)


def _version_callback(value: bool) -> None:
    if value:
        typer.echo(f"nb {__version__}")
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
    """Node-builder CLI root callback."""


register_commands(app)


def run() -> None:
    """Console-script entrypoint."""
    app()


if __name__ == "__main__":
    run()
