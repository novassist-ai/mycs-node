# Design

Architecture and contracts for the vpn-node-builder CLI.

## Runtime model

| Audience | Runtime |
|----------|---------|
| End users | Docker image `novassist/vpn-node-builder`; host launcher (Homebrew / Windows zip); project cwd mounted at `/work` |
| Developers | Native Python package (`pip install -e .`) in `apps/clients/vpn-node-builder` |

One codebase serves both. Packaging differs; command behavior does not.

## Components

```
vpnb (Typer)
├── commands/     # init, deploy, destroy, show-*, vpn, tunnel, doctor
├── core/         # paths, workspace, EULA, env, init stubs, process
├── cloud/        # CLI credentials session, regions, nodes, power
├── terraform/    # backend ensure, init / plan / apply / destroy / taint
└── ui/           # Rich tables / prompts
```

Outside this package:

| Path | Role |
|------|------|
| `cloud/cookbook` | Terraform recipes (`sandbox`, `approuter`, …) |
| `libs/shared/app/golang` | `system-env`, `vagrant-exec`, `vboxmanage-exec` for local recipes |

## Path contracts

| Location | Path |
|----------|------|
| Container work mount | `/work` |
| In-repo cookbook | `<repo>/cloud/cookbook` |
| Image cookbook (Phase 6) | `/usr/local/lib/vpn-node-builder/cloud/cookbook` |
| Override | `VPNB_COOKBOOK_PATH` |

## Workspace layout

`vpnb` walks up from the current directory looking for `.workspace`. If none is
found, it creates `.workspace` in the cwd.

```
<working_dir>/
├── cloud-creds.sh              # vpnb init
├── build-vars.sh               # vpnb init
├── configs/<node_name>/        # VPN downloads
└── .workspace/
    ├── run/
    │   ├── eula_accepted
    │   └── <node_type>/<cloud>/[<region>/]
    │       ├── output.json
    │       ├── *.pem
    │       ├── client_tunnel   # optional
    │       └── .terraform/
    └── templates/              # symlinks → cookbook recipes/<node_type>
```

## Module map

| Module | Responsibility |
|--------|----------------|
| `core/paths.py` | Repo / cookbook / utils resolution |
| `core/workspace.py` | `.workspace`, template links, recipe validation |
| `core/eula.py` | EULA gate (`https://novassist.ai/legal/`) |
| `core/environment.py` | Soft/hard tool checks; bash-source control files |
| `core/debug.py` | `-d/--debug` trace (`+ cmd`) for subprocesses |
| `core/usage.py` | Usage banners printed before unknown NODE_TYPE/CLOUD errors |
| `core/credentials.py` | Required env vars per cloud |
| `core/init_files.py` | Stub file contents for `vpnb init` |
| `cloud/` | Provider session, regions, inventory, start/stop |
| `terraform/` | Backend + lifecycle; tee plan/apply/destroy to logs with composable console filters |

## Cloud targets

| Cloud id | Regions | Notes |
|----------|---------|--------|
| `aws`, `azure`, `google` | yes | Public IaaS; remote Terraform state |
| `vagrant-vbox` | no | Local VM via Vagrant → VirtualBox |
| `docker` | no | Local/container recipe path |

## Terraform layout

- Recipe templates: `cloud/cookbook/recipes/<node_type>/<cloud>/`
- Invoked with `terraform -chdir=<template_dir>`
- Per-deployment `TF_DATA_DIR=<run_dir>/.terraform`
- Backends: `s3`, `azurerm`, `gcs`, or `local` (from recipe `cloud.tf`)

## Validation policy

| Entry point | Behavior |
|-------------|----------|
| `vpnb doctor` | Soft: report missing tools/files, still exit success |
| Deploy / destroy / regions / VPN / … | Hard: EULA + tools + control files + recipe validation |

## EULA

Interactive acceptance once per workspace. Skip only with `VPNB_SKIP_EULA=1`
(tests/CI).

## Bastion image (`TF_VAR_bastion_image_name` + publisher locators)

Sandbox public-cloud recipes require `var.bastion_image_name` (common input; no
default) plus a cloud-specific publisher locator (no Terraform default):

| Cloud | Variable | Meaning |
|-------|----------|---------|
| AWS | `bastion_image_owner` | AMI owner account ID |
| Google | `bastion_image_bucket_prefix` | GCS bucket prefix (`${prefix}_${region}/…`) |
| Azure | `bastion_image_storage_account_prefix`, `bastion_image_container` | VHD blob location |
| OpenStack/OVH | *(none)* | Glance match by image name/regex only |

| Source | Value |
|--------|--------|
| Docker image build (dev) | Latest `mycs-node-image_X.Y.Z-devN` + dev publisher locators |
| Docker image build (prod) | Latest `mycs-node-image_X.Y.Z` + prod publisher locators |
| Native dev | Set in `build-vars.sh` or export before `vpnb deploy-node` |

Naming uses `mycs-node-image_*` only — no `appbricks-*` AMI lookups.

`vagrant-vbox` maps `mycs-node-image_<version>` → Vagrant box
`mycloudspace/mycs-node-image` at version `<version>` (e.g. `dev`, `1.2.3`).
