# MyCloudSpace Node

[![Build Status](https://github.com/novassist-ai/mycs-node/actions/workflows/build-image-dev.yml/badge.svg)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-image-dev.yml)
[![Build Status](https://github.com/novassist-ai/mycs-node/actions/workflows/build-image-prod.yml/badge.svg)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-image-prod.yml)
[![Build Status](https://github.com/novassist-ai/mycs-node/actions/workflows/build-vpn-node-builder-dev/badge.svg)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-vpn-node-builder-dev.yml)
[![Build Status](https://github.com/novassist-ai/mycs-node/actions/workflows/build-vpn-node-builder-prod/badge.svg)](https://github.com/novassist-ai/mycs-node/actions/workflows/build-vpn-node-builder-prod.yml)

MyCS Bastion Node and Cloud Network Automation.

## Repository layout

| Path | Description |
|------|-------------|
| [`image/`](image/) | Packer build tooling, bootstrap scripts, and image design docs |
| [`service/`](service/) | mycs-node control plane binary and runtime |
| [`cloud/`](cloud/) | Terraform modules, cookbook, and deployment tests |

Image build documentation: [image/README.md](image/README.md).
