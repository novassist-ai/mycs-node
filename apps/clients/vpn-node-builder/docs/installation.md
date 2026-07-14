# Installation

End users run `vpnb` through a **host launcher** that executes the Docker image
`ghcr.io/novassist-ai/vpn-node-builder`. The Python CLI, Terraform, cloud CLIs,
cookbook, Go helpers, and default bastion image name are inside the image. Your
project directory is mounted at `/work`.

## Requirements

- [Docker](https://docs.docker.com/get-docker/) installed and running
- Network access to pull from GitHub Container Registry (GHCR)

## Channels

| Command | Image | Bastion baked into image |
|---------|-------|--------------------------|
| `vpnb` | `ghcr.io/novassist-ai/vpn-node-builder:latest` | Prod semver AMI (`mycs-bastion_X.Y.Z`) |
| `vpnb-dev` | `ghcr.io/novassist-ai/vpn-node-builder:dev` | CI tip (`mycs-bastion_D.*`) |

Override either binary:

```bash
export VPNB_IMAGE=ghcr.io/novassist-ai/vpn-node-builder:0.0.3
vpnb doctor
```

## macOS / Linux (Homebrew)

Tap: [`novassist-ai/homebrew-tap`](https://github.com/novassist-ai/homebrew-tap)

```bash
brew tap novassist-ai/tap
brew install --HEAD vpn-node-builder

vpnb-dev --help          # auto-pulls :dev if missing locally
vpnb-dev update          # force re-download :dev
vpnb --help              # prod :latest (once published)
```

Host launcher helpers (not Typer commands):

| Command | Behavior |
|---------|----------|
| _(none)_ | Auto-pulls the channel image if it is not present locally |
| `pull` | `docker pull` for the channel image |
| `update` | Deletes the local image, then pulls a fresh copy |

The formula installs the launcher as **`vpnb`** and a symlink **`vpnb-dev`**. It does
**not** install Python, Terraform, or cloud CLIs on the host — those run inside
the container.

Stable (versioned) formula installs will ship when Phase 7 publishes launcher
release assets and bumps the tap SHA; until then use `--HEAD`.

## Windows (release zip)

From a release artifact (Phase 7 publishes the zip):

1. Extract `vpnb.cmd` / `vpnb.ps1` (prod) and `vpnb-dev.cmd` / `vpnb-dev.ps1` (dev) onto
   your `PATH`.
2. Ensure Docker Desktop is running.
3. Run `vpnb --help` or `vpnb-dev --help` (auto-pulls if needed); use `update` to force refresh.

Scripts live in `apps/clients/vpn-node-builder/scripts/` in the repository until
release packaging is wired.

## Direct Docker

```bash
docker pull ghcr.io/novassist-ai/vpn-node-builder:latest
docker run --privileged --rm -it \
  -p 4495:4495 -p 4495:4495/udp \
  -v "$(pwd):/work" -w /work \
  ghcr.io/novassist-ai/vpn-node-builder:latest \
  --help
```

## Bastion image version

The image is built with a default `TF_VAR_bastion_image_name`:

| Build env | Bastion image name |
|-----------|-------------------|
| **local CLI (`dev`)** | `mycs-bastion_dev` (fixed; build via Packer with `DEV_BUILD=dev`) |
| **CI (`ci` / Actions)** | Latest `mycs-bastion_D.*` AMI, or the name passed from the bastion workflow |
| **prod** | Latest `mycs-bastion_X.Y.Z` AMI (resolved at image build via AWS) |

No `appbricks-*` image names are used. To override for a single **native**
deploy, set in `build-vars.sh`:

```bash
export TF_VAR_bastion_image_name=mycs-bastion_dev
```

## Build the image locally

From the `mycs-node` repository root:

```bash
./apps/clients/vpn-node-builder/scripts/build-docker.sh dev dev
docker run --rm ghcr.io/novassist-ai/vpn-node-builder:dev --version
```

See [Development](development.md) for native (non-Docker) work.

## After install

```bash
mkdir my-nodes && cd my-nodes
vpnb init
# edit cloud-creds.sh and build-vars.sh
vpnb doctor
```

See [Usage](usage.md) for deploy and VPN commands.
