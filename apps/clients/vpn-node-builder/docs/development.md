# Development

Develop and test `vpnb` **natively** in a Python virtualenv. End-user distribution
is Docker-only ([Installation](installation.md)).

## Prerequisites

| Tool | When needed |
|------|-------------|
| Python **3.12+** | Always |
| `pip` (or `uv`) | Always |
| Terraform, `jq`, `aws`, `az`, `gcloud` | Real deploy / region commands |
| Vagrant + VirtualBox | `vagrant-vbox` recipes |
| Go **1.20+** | Rebuilding `libs/shared/app/golang` helpers |
| Docker | Building or smoke-testing the packaged image |

Repo paths:

| Path | Role |
|------|------|
| `apps/clients/vpn-node-builder` | This CLI |
| `cloud/cookbook` | Terraform recipes |
| `libs/shared/app/golang` | `system-env`, `vagrant-exec`, `vboxmanage-exec` |

---

## macOS

```bash
brew install python@3.12

cd /path/to/mycs-node/apps/clients/vpn-node-builder
python3.12 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -e ".[dev]"

vpnb --help
vpnb doctor
pytest
```

Rebuild Go helpers:

```bash
# from mycs-node repo root
./apps/clients/vpn-node-builder/scripts/build-utils.sh :dev:clean-all:
```

---

## Linux

```bash
sudo apt update
sudo apt install -y python3.12 python3.12-venv python3-pip

cd /path/to/mycs-node/apps/clients/vpn-node-builder
python3.12 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -e ".[dev]"

vpnb --help
pytest
```

---

## Windows

```powershell
cd C:\path\to\mycs-node\apps\clients\vpn-node-builder
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e ".[dev]"
vpnb --help
```

Fallback: `python -m vpn_node_builder.cli --help`

---

## Docker image (local)

Build from the **repository root**:

```bash
./apps/clients/vpn-node-builder/scripts/build-docker.sh dev dev
```

Smoke:

```bash
docker run --rm novassist/vpn-node-builder:dev --version
docker run --rm -v "$(pwd):/work" -w /work novassist/vpn-node-builder:dev doctor
```

Resolve bastion image name:

```bash
./apps/clients/vpn-node-builder/scripts/get-cloud-image.sh dev    # → mycs-node-image_dev (local CLI)
./apps/clients/vpn-node-builder/scripts/get-cloud-image.sh ci     # → latest mycs-node-image_X.Y.Z-devN
./apps/clients/vpn-node-builder/scripts/get-cloud-image.sh prod   # → latest mycs-node-image_X.Y.Z
```

CI: `.github/workflows/build-vpn-node-builder-dev.yml` (branch `dev`, pushes
`ghcr.io/novassist-ai/vpn-node-builder:dev`) and `build-vpn-node-builder-prod.yml`
(branch `main`, pushes `:latest` and optional `:0.0.N`). PRs to `dev` build and
smoke only (no push).

---

## Native exercise workflow

```bash
cd /path/to/a-project-dir
export VPNB_COOKBOOK_PATH=/path/to/mycs-node/cloud/cookbook
export TF_VAR_bastion_image_name=mycs-bastion_dev   # required for native deploy
vpnb init
vpnb doctor
vpnb deploy-node sandbox aws -r us-east-1 -s
```

Inside the `mycs-node` tree, cookbook discovery usually works without
`VPNB_COOKBOOK_PATH`. The Docker image sets `TF_VAR_bastion_image_name` at build
time; native runs need it in `build-vars.sh` or the environment.

---

## Environment overrides

| Variable | Purpose |
|----------|---------|
| `VPNB_COOKBOOK_PATH` | Cookbook root |
| `VPNB_SKIP_EULA` | Skip EULA (tests/CI only) |
| `TF_VAR_bastion_image_name` | Bastion AMI/box (`mycs-bastion_*`) |
| `VPNB_IMAGE` / `VPN_NODE_BUILDER_IMAGE` | Full image ref (overrides `vpnb` / `vpnb-dev` defaults) |
| `VPNB_REGISTRY_IMAGE` | Registry repo without tag (default `ghcr.io/novassist-ai/vpn-node-builder`) |
| `EXT_COOKBOOK_PATH` | External cookbooks root |

---

## Tests and style

```bash
pytest
ruff check src tests
ruff format src tests
```
