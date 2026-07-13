# Node Builder CLI (`nb`)

Deploy and manage MyCS VPN node environments from Terraform cookbooks in
[`cloud/cookbook`](../../../cloud/cookbook).

## Overview

`nb` initializes a project workspace, deploys and destroys node recipes across
cloud providers (and local `vagrant-vbox` / `docker` targets), and helps with
VPN client config and optional traffic-masking tunnels.

| Audience | How you run `nb` |
|----------|------------------|
| **End users** | Thin host launcher → Docker image `novassist/node-builder` (cwd → `/work`) |
| **Developers** | Native Python 3.12+ virtualenv in this folder |

**Packaging (Phase 6):** `Dockerfile`, host launchers (`scripts/nb-docker`, `nb.cmd`, `nb.ps1`),
`build-docker.sh`, Homebrew formula `node-builder`, CI workflow
`build-node-builder-dev.yml` / `build-node-builder-prod.yml`. Registry publish is Phase 7.

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
cd apps/clients/node-builder
python3.12 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -e ".[dev]"
nb --help
pytest
```

Platform-specific prerequisites and Go util builds:
[Development](docs/development.md).

Minimal first run in a project directory:

```bash
mkdir -p ~/mycs-nodes && cd ~/mycs-nodes
export NB_COOKBOOK_PATH=/path/to/mycs-node/cloud/cookbook   # if not inside the repo
nb init
# edit cloud-creds.sh and build-vars.sh
nb doctor
nb show-regions aws
nb deploy-node sandbox aws -r us-east-1 -s    # plan only
```

## License

Same as the `mycs-node` repository (GPL-3.0).
