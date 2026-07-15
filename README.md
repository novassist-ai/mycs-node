# MyCloudSpace Node

MyCS Bastion Node and Cloud Network Automation.

## CI status

| Workflow | Status |
|----------|--------|
| Bastion images (dev) | [![Build Bastion Images (dev)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-image-dev.yml/badge.svg?branch=dev)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-image-dev.yml?query=branch%3Adev) |
| Bastion images (prod) | [![Build Bastion Images (prod)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-image-prod.yml/badge.svg?branch=main)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-image-prod.yml?query=branch%3Amain) |
| vpn-node-builder (dev) | [![Build vpn-node-builder (dev)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-vpn-node-builder-dev.yml/badge.svg?branch=dev)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-vpn-node-builder-dev.yml?query=branch%3Adev) |
| vpn-node-builder (prod) | [![Build vpn-node-builder (prod)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-vpn-node-builder-prod.yml/badge.svg?branch=main)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-vpn-node-builder-prod.yml?query=branch%3Amain) |

## Repository layout

| Path | Description |
|------|-------------|
| [`image/`](image/) | Packer build tooling, bootstrap scripts, and image design docs |
| [`service/`](service/) | mycs-node control plane binary and runtime |
| [`cloud/`](cloud/) | Terraform modules, cookbook, and deployment tests |

Image build documentation: [image/README.md](image/README.md).
