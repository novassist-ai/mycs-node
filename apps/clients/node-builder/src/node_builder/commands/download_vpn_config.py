"""``nb download-vpn-config``."""

from __future__ import annotations

import json
import platform
import subprocess
import time
import urllib.error
import urllib.request
from base64 import b64encode
from pathlib import Path

import typer
from rich.console import Console

from node_builder.commands._context import (
    prepare_command_context,
    require_run_dir,
    resolve_deployment,
)
from node_builder.core.errors import NodeBuilderError

console = Console()


def _download(
    url: str,
    dest: Path,
    *,
    user: str,
    password: str,
    skip_ssl: bool,
) -> None:
    dest.unlink(missing_ok=True)
    token = b64encode(f"{user}:{password}".encode()).decode()
    while True:
        try:
            request = urllib.request.Request(
                url,
                headers={"Authorization": f"Basic {token}"},
            )
            # nosec - intentional for self-signed bastion certs when not certified
            context = None
            if skip_ssl:
                import ssl

                context = ssl._create_unverified_context()
            with urllib.request.urlopen(request, context=context, timeout=30) as resp:
                dest.write_bytes(resp.read())
            return
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError):
            console.print("Waiting for VPN node to become available...")
            time.sleep(5)


def download_vpn_config(
    node_type: str = typer.Argument(...),
    cloud: str = typer.Argument(...),
    region: str | None = typer.Option(None, "-r", "--region"),
    user: str = typer.Option(..., "-u", "--user"),
    password: str = typer.Option(..., "-p", "--password"),
    debug: bool = typer.Option(False, "-d", "--debug", hidden=True),
) -> None:
    """Download VPN client configuration from a deployed node."""
    _ = debug
    try:
        if not user or not password:
            raise NodeBuilderError(
                "The user name and password of the VPN user cannot be empty."
            )
        ctx = prepare_command_context()
        validated, run_dir = resolve_deployment(
            ctx, node_type=node_type, cloud=cloud, region=region
        )
        require_run_dir(run_dir)
        output_path = run_dir / "output.json"
        if not output_path.is_file():
            raise NodeBuilderError("output.json not found for this deployment.")

        data = json.loads(output_path.read_text(encoding="utf-8"))
        vpn_type = str((data.get("cb_vpn_type") or {}).get("value") or "")
        if not vpn_type or vpn_type == "null":
            raise NodeBuilderError("Node does not provide a VPN service.")
        if vpn_type == "wireguard":
            console.print(
                "\n[yellow]The Space node is configured with a wireguard VPN which "
                "can be configured only via the MyCS node service API.[/yellow]"
            )
            return

        node_name = str((data.get("cb_vpc_name") or {}).get("value") or "node")
        masking = str((data.get("cb_vpn_masking_available") or {}).get("value") or "")
        first = (data.get("cb_managed_instances", {}).get("value") or [{}])[0]
        bastion_fqdn = str(first.get("fqdn") or "")
        bastion_port = str(first.get("api_port") or "443")
        dns_configured = str((data.get("cb_dns_configured") or {}).get("value") or "")
        if dns_configured == "true":
            host = bastion_fqdn
        else:
            host = str(first.get("public_ip") or "")
        if bastion_port and bastion_port not in {"443", "null", ""}:
            host = f"{host}:{bastion_port}"

        skip_ssl = (
            not ctx.environ.get("TF_VAR_certify_bastion")
            or ctx.environ.get("TF_VAR_certify_bastion") == "false"
        )
        console.print(
            f'\n[green]Downloading VPN configs from '
            f'"https://{host}/static/~{user}/"...[/green]'
        )

        if masking.lower() in {"yes", "true"}:
            tunnel = run_dir / "client_tunnel"
            _download(
                f"https://{host}/static/~{user}/client_tunnel",
                tunnel,
                user=user,
                password=password,
                skip_ssl=skip_ssl,
            )
            tunnel.chmod(0o755)

        # configs live next to the project working dir
        configs_dir = validated.workspace.working_dir / "configs" / node_name
        configs_dir.mkdir(parents=True, exist_ok=True)
        deployment_name = ctx.environ.get("TF_VAR_name") or "node"
        os_type = platform.system()

        if os_type == "Darwin":
            if vpn_type == "openvpn":
                file_name = f"{deployment_name}.ovpn"
            elif vpn_type == "ipsec":
                file_name = f"{deployment_name}.mobileconfig"
            else:
                raise NodeBuilderError(f"Unknown VPN type '{vpn_type}'.")
            dest = configs_dir / file_name
            _download(
                f"https://{host}/static/~{user}/{file_name}",
                dest,
                user=user,
                password=password,
                skip_ssl=skip_ssl,
            )
            subprocess.run(["open", str(dest)], check=False)
        elif os_type == "Linux":
            if vpn_type == "openvpn":
                zipped = configs_dir / "openvpn-config.tunnelblick.zip"
                _download(
                    f"https://{host}/static/~{user}/openvpn-config.tunnelblick.zip",
                    zipped,
                    user=user,
                    password=password,
                    skip_ssl=skip_ssl,
                )
                for tblk in configs_dir.glob("*.tblk"):
                    if tblk.is_dir():
                        import shutil

                        shutil.rmtree(tblk)
                subprocess.run(
                    ["unzip", "-q", "-o", str(zipped), "-d", str(configs_dir)],
                    check=False,
                )
                zipped.unlink(missing_ok=True)
                ovpn = configs_dir / f"{deployment_name}.ovpn"
                _download(
                    f"https://{host}/static/~{user}/{deployment_name}.ovpn",
                    ovpn,
                    user=user,
                    password=password,
                    skip_ssl=skip_ssl,
                )
            elif vpn_type == "ipsec":
                mobile = configs_dir / f"{deployment_name}.mobileconfig"
                _download(
                    f"https://{host}/static/~{user}/{deployment_name}.mobileconfig",
                    mobile,
                    user=user,
                    password=password,
                    skip_ssl=skip_ssl,
                )
                p12 = configs_dir / f"{user}.p12"
                _download(
                    f"https://{host}/static/~{user}/{user}.p12",
                    p12,
                    user=user,
                    password=password,
                    skip_ssl=skip_ssl,
                )
            else:
                raise NodeBuilderError(f"Unknown VPN type '{vpn_type}'.")
            console.print(
                f'\n[green]VPN client config files downloaded to '
                f'"configs/{node_name}/":[/green]\n'
            )
            for path in sorted(configs_dir.iterdir()):
                console.print(f'- "{path.name}"')
            if vpn_type == "openvpn":
                console.print(
                    "\nImport it to your OpenVPN or Tunnelblick client and login using:\n"
                )
                console.print(f"  user: {user}")
                console.print(f"  password: {password}\n")
            else:
                console.print(
                    f'\nImport the "{user}.p12" / mobileconfig profile as appropriate '
                    "for your client.\n"
                )
        else:
            raise NodeBuilderError(
                "Unable to determine OS type for VPN download. "
                f"Download manually from https://{host}/static/~{user}"
            )
    except NodeBuilderError as exc:
        console.print(f"[red]ERROR![/red] {exc}")
        raise typer.Exit(code=1) from exc
