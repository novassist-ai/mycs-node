# MyCloudSpace Node

MyCS Bastion Node and Cloud Network Automation.

## CI status

| Workflow | Status |
|----------|--------|
| Bastion images (dev) | [![Build Bastion Images (dev)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-image-dev.yml/badge.svg?branch=dev)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-image-dev.yml?query=branch%3Adev) |
| Bastion images (prod) | [![Build Bastion Images (prod)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-image-prod.yml/badge.svg?branch=main)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-image-prod.yml?query=branch%3Amain) |
| vpn-node-builder (dev) | [![Build vpn-node-builder (dev)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-vpn-node-builder-dev.yml/badge.svg?branch=dev)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-vpn-node-builder-dev.yml?query=branch%3Adev) |
| vpn-node-builder (prod) | [![Build vpn-node-builder (prod)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-vpn-node-builder-prod.yml/badge.svg?branch=main)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-vpn-node-builder-prod.yml?query=branch%3Amain) |

## Tools

Client tools built and published from this repository.

### vpn-node-builder (`vpnb`)

CLI to deploy and manage MyCS VPN nodes across cloud regions. End users run a
thin host launcher that executes the Docker image
`ghcr.io/novassist-ai/vpn-node-builder` (`vpnb` → `:latest`, `vpnb-dev` → `:dev`).

**Install (macOS / Linux):**

```bash
brew tap novassist-ai/tap
brew install vpn-node-builder

vpnb --help
vpnb-dev --help
```

Requires [Docker](https://docs.docker.com/get-docker/).

| Doc | Description |
|-----|-------------|
| [Installation](apps/clients/vpn-node-builder/docs/installation.md) | Homebrew, Windows, Docker install |
| [Usage](apps/clients/vpn-node-builder/docs/usage.md) | Workflow and command reference |

More docs: [vpn-node-builder README](apps/clients/vpn-node-builder/README.md).

## Repository layout

| Path | Description |
|------|-------------|
| [`apps/`](apps/) | Client applications and CLIs (e.g. vpn-node-builder) |
| [`image/`](image/) | Packer build tooling, bootstrap scripts, and image design docs |
| [`service/`](service/) | mycs-node control plane binary and runtime |
| [`cloud/`](cloud/) | Terraform modules, cookbook, and deployment tests |

Image build documentation: [image/README.md](image/README.md).
