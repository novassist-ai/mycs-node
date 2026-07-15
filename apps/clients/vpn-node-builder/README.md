# Node Builder CLI (`vpnb`)

Deploy and manage MyCS VPN node environments from Terraform cookbooks in
[`cloud/cookbook`](../../../cloud/cookbook).

## Overview

`vpnb` initializes a project workspace, deploys and destroys node recipes across
cloud providers (and local `vagrant-vbox` / `docker` targets), and helps with
VPN client config and optional traffic-masking tunnels.

| Audience | How you run `vpnb` |
|----------|------------------|
| **End users** | Thin host launcher → Docker image `novassist/vpn-node-builder` (cwd → `/work`) |
| **Developers** | Native Python 3.12+ virtualenv in this folder |

**Packaging (Phase 6):** `Dockerfile`, host launchers (`scripts/vpnb-docker` as `vpnb` /
`vpnb-dev`, Windows `vpnb*.cmd` / `vpnb*.ps1`), `build-docker.sh`, Homebrew formula
`vpn-node-builder` (`vpnb` → GHCR `:latest`, `vpnb-dev` → `:dev`). CI workflows
`build-vpn-node-builder-dev.yml` / `build-vpn-node-builder-prod.yml` (git tags `vpnb_*`;
GHCR tags unprefixed `:dev` / `:latest` / `:X.Y.Z[-devN]`). Stable formula bumps are Phase 7.

## Documentation

| Doc | Contents |
|-----|----------|
| [Usage](docs/usage.md) | Typical workflow and command reference |
| [Installation](docs/installation.md) | End-user install (Homebrew / Windows zip / Docker) |
| [Development](docs/development.md) | Native setup on macOS, Linux, and Windows |
| [Design](docs/design.md) | Runtime model, layout, cloud targets, paths |
| [Troubleshooting](docs/troubleshooting.md) | Common failures and fixes |

## Quick start (developers)

```bash
cd apps/clients/vpn-node-builder
python3.12 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -e ".[dev]"
vpnb --help
pytest
```

Platform-specific prerequisites and Go util builds:
[Development](docs/development.md).

Minimal first run in a project directory:

```bash
mkdir -p ~/mycs-nodes && cd ~/mycs-nodes
export VPNB_COOKBOOK_PATH=/path/to/mycs-node/cloud/cookbook   # if not inside the repo
vpnb init
# edit cloud-creds.sh and build-vars.sh
vpnb doctor
vpnb show-regions aws
vpnb deploy-node sandbox aws -r us-east-1 -s    # plan only
```

## License

Same as the `mycs-node` repository (GPL-3.0).
