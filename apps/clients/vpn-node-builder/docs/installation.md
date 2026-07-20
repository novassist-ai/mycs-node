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
| `vpnb` | `ghcr.io/novassist-ai/vpn-node-builder:latest` | Prod semver AMI (`mycs-node-image_X.Y.Z`) |
| `vpnb-dev` | `ghcr.io/novassist-ai/vpn-node-builder:dev` | CI tip (`mycs-node-image_X.Y.Z-devN`) |

Override either binary:

```bash
export VPNB_IMAGE=ghcr.io/novassist-ai/vpn-node-builder:0.0.3
vpnb doctor
```

## macOS / Linux (Homebrew)

Tap: [`novassist-ai/homebrew-tap`](https://github.com/novassist-ai/homebrew-tap)

```bash
brew tap novassist-ai/tap
brew install vpn-node-builder

vpnb --help              # auto-pulls :latest if missing locally
vpnb-dev --help          # auto-pulls :dev if missing locally
vpnb update              # force re-download :latest
vpnb-dev update          # force re-download :dev
```

Optional tip install of the launcher from the `dev` branch:

```bash
brew install --HEAD vpn-node-builder
```

Host launcher helpers (not Typer commands):

| Command | Behavior |
|---------|----------|
| _(none)_ | Auto-pulls the channel image if it is not present locally |
| `pull` | `docker pull` for the channel image |
| `update` | Deletes the local image, then pulls a fresh copy |

The formula installs the launcher as **`vpnb`** and a symlink **`vpnb-dev`**. It does
**not** install Python, Terraform, or cloud CLIs on the host — those run inside
the container. The stable formula tracks the `vpnb_X.Y.Z` git tag (launcher
script); Docker images are still pulled as `:latest` / `:dev` (or a pin via
`VPNB_IMAGE`).

After each successful **prod** vpn-node-builder build, CI bumps
[`novassist-ai/homebrew-tap`](https://github.com/novassist-ai/homebrew-tap)
(`Formula/vpn-node-builder.rb`) via `cicd/scripts/bump-homebrew-vpn-node-builder.sh`.
That requires the `HOMEBREW_TAP_TOKEN` secret on `mycs-node` (PAT with
`contents:write` on the tap). Dev builds do **not** bump the formula — refresh
the dev image with `vpnb-dev update`.

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

The image is built with a default `TF_VAR_bastion_image_name` and cloud-specific publisher locators:

| Build env | Bastion image name |
|-----------|-------------------|
| **local CLI (`dev`)** | `mycs-node-image_dev` (fixed; build via Packer with `DEV_BUILD=dev`) |
| **CI (`ci` / Actions)** | Latest `mycs-node-image_X.Y.Z-devN` AMI, or the name passed from the bastion workflow |
| **prod** | Latest `mycs-node-image_X.Y.Z` AMI (resolved at image build via AWS) |

| Locator | dev Docker | prod Docker |
|---------|------------|-------------|
| `TF_VAR_bastion_image_owner` (AWS) | `244289018343` | `975050267636` |
| `TF_VAR_bastion_image_bucket_prefix` (GCP) | `mycsimages` | `mycsimages` |
| `TF_VAR_bastion_image_storage_account_prefix` (Azure) | `mycs` | `mycs` |
| `TF_VAR_bastion_image_container` (Azure) | `nodeimage` | `nodeimage` |


No `appbricks-*` image names are used. `vpnb doctor` shows the bastion image
name/pattern baked into the CLI/image (`TF_VAR_bastion_image_name`), plus
publisher locators (`TF_VAR_bastion_image_owner`, GCS/Azure prefixes).

On AWS the name is a **glob** (`*` / `?`), not a regex — e.g.
`mycs-node-image_0.1.0-dev*` matches `mycs-node-image_0.1.0-dev0`. A regex-style
`.*` is also accepted and treated as `*`. Multiple matches use the most recent AMI.

Azure managed-image lookup uses the same wildcards (plus `_${region}` suffix) and
picks the lexicographically last name. Google project images use the same
wildcards after converting to GCP naming (`mycs-node-image-0-1-0-dev*`) and
`most_recent` by creation time.

To override for deployments, set in `build-vars.sh`:

```bash
export TF_VAR_bastion_image_name=mycs-node-image_0.1.0-dev*
# AWS AMI owner (dev vs prod accounts differ)
export TF_VAR_bastion_image_owner=244289018343
# Google / Azure publisher locators (usually unchanged)
export TF_VAR_bastion_image_bucket_prefix=mycsimages
export TF_VAR_bastion_image_storage_account_prefix=mycs
export TF_VAR_bastion_image_container=nodeimage
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
