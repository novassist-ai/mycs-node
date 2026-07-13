# Development

Develop and test `nb` **natively** in a Python virtualenv. End-user distribution
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
| `apps/clients/node-builder` | This CLI |
| `cloud/cookbook` | Terraform recipes |
| `libs/shared/app/golang` | `system-env`, `vagrant-exec`, `vboxmanage-exec` |

---

## macOS

```bash
brew install python@3.12

cd /path/to/mycs-node/apps/clients/node-builder
python3.12 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -e ".[dev]"

nb --help
nb doctor
pytest
```

Rebuild Go helpers:

```bash
# from mycs-node repo root
./apps/clients/node-builder/scripts/build-utils.sh :dev:clean-all:
```

---

## Linux

```bash
sudo apt update
sudo apt install -y python3.12 python3.12-venv python3-pip

cd /path/to/mycs-node/apps/clients/node-builder
python3.12 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -e ".[dev]"

nb --help
pytest
```

---

## Windows

```powershell
cd C:\path\to\mycs-node\apps\clients\node-builder
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e ".[dev]"
nb --help
```

Fallback: `python -m node_builder.cli --help`

---

## Docker image (local)

Build from the **repository root**:

```bash
./apps/clients/node-builder/scripts/build-docker.sh dev dev
```

Smoke:

```bash
docker run --rm novassist/node-builder:dev --version
docker run --rm -v "$(pwd):/work" -w /work novassist/node-builder:dev doctor
```

Resolve bastion image name:

```bash
./apps/clients/node-builder/scripts/get-cloud-image.sh dev    # → mycs-bastion_dev (local CLI)
./apps/clients/node-builder/scripts/get-cloud-image.sh ci     # → latest mycs-bastion_D.*
./apps/clients/node-builder/scripts/get-cloud-image.sh prod   # → latest mycs-bastion_X.Y.Z
```

CI: `.github/workflows/build-node-builder-dev.yml` (branch `dev`) and
`build-node-builder-prod.yml` (branch `main`) build and smoke-test on push / dispatch.

---

## Native exercise workflow

```bash
cd /path/to/a-project-dir
export NB_COOKBOOK_PATH=/path/to/mycs-node/cloud/cookbook
export TF_VAR_bastion_image_name=mycs-bastion_dev   # required for native deploy
nb init
nb doctor
nb deploy-node sandbox aws -r us-east-1 -s
```

Inside the `mycs-node` tree, cookbook discovery usually works without
`NB_COOKBOOK_PATH`. The Docker image sets `TF_VAR_bastion_image_name` at build
time; native runs need it in `build-vars.sh` or the environment.

---

## Environment overrides

| Variable | Purpose |
|----------|---------|
| `NB_COOKBOOK_PATH` | Cookbook root |
| `NB_SKIP_EULA` | Skip EULA (tests/CI only) |
| `TF_VAR_bastion_image_name` | Bastion AMI/box (`mycs-bastion_*`) |
| `NB_IMAGE` / `NODE_BUILDER_IMAGE` | Full image ref (overrides `nb` / `nb-dev` defaults) |
| `NB_REGISTRY_IMAGE` | Registry repo without tag (default `ghcr.io/novassist-ai/node-builder`) |
| `EXT_COOKBOOK_PATH` | External cookbooks root |

---

## Tests and style

```bash
pytest
ruff check src tests
ruff format src tests
```
