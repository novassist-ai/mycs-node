# Installation

End users run `nb` through a **host launcher** that executes the Docker image
`novassist/node-builder`. The Python CLI, Terraform, cloud CLIs, cookbook, Go
helpers, and default bastion image name are inside the image. Your project
directory is mounted at `/work`.

## Requirements

- [Docker](https://docs.docker.com/get-docker/) installed and running
- Network access to pull `novassist/node-builder` (when published to a registry)

## macOS / Linux (Homebrew)

Tap: [`novassist-ai/homebrew-tap`](https://github.com/novassist-ai/homebrew-tap)

```bash
brew tap novassist-ai/tap
brew install --HEAD node-builder
docker pull novassist/node-builder:latest
nb --help
```

The formula installs the `nb` launcher script only. It does **not** install
Python, Terraform, or cloud CLIs on the host — those run inside the container.

Default image tag: `novassist/node-builder:latest`

Override:

```bash
export NB_IMAGE=novassist/node-builder:dev
nb doctor
```

## Windows (release zip)

From a release artifact (Phase 7 publishes the zip):

1. Extract `nb.cmd` and `nb.ps1` to a directory on your `PATH`.
2. Ensure Docker Desktop is running.
3. `docker pull novassist/node-builder:latest`
4. Run `nb --help` from your project directory.

Scripts live in `apps/clients/node-builder/scripts/` in the repository until
release packaging is wired.

## Direct Docker

Equivalent to the launcher:

```bash
docker pull novassist/node-builder:latest
docker run --privileged --rm -it \
  -p 4495:4495 -p 4495:4495/udp \
  -v "$(pwd):/work" -w /work \
  novassist/node-builder:latest \
  --help
```

## Bastion image version

The image is built with a default `TF_VAR_bastion_image_name`:

| Build env | Bastion image name |
|-----------|-------------------|
| **local CLI (`dev`)** | `mycs-bastion_dev` (fixed; build via Packer with `DEV_BUILD=dev`) |
| **CI (`ci` / Actions)** | Latest `mycs-bastion_D.*` AMI, or the name passed from the bastion workflow |
| **prod** | Latest `mycs-bastion_X.Y.Z` AMI (resolved at image build via AWS) |

No `appbricks-*` image names are used. To override for a single deploy when
running natively, set in `build-vars.sh`:

```bash
export TF_VAR_bastion_image_name=mycs-bastion_dev
```

## Build the image locally

From the `mycs-node` repository root:

```bash
./apps/clients/node-builder/scripts/build-docker.sh dev dev
docker run --rm novassist/node-builder:dev --version
```

See [Development](development.md) for native (non-Docker) work.

## After install

```bash
mkdir my-nodes && cd my-nodes
nb init
# edit cloud-creds.sh and build-vars.sh
nb doctor
```

See [Usage](usage.md) for deploy and VPN commands.
