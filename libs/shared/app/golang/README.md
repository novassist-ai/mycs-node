# Shared Go utilities (node-builder)

Small CLI helpers used by local Terraform recipes (`sandbox/vagrant-vbox`, `approuter/docker`) via the Terraform `shell` provider. They are built into release zips and into the `novassist/node-builder` Docker image; end users do not invoke them directly.

## Commands

| Binary | Role |
|--------|------|
| `system-env` | Emits JSON describing OS/arch, paths, default network, DNS, and whether Vagrant/VirtualBox are installed |
| `vagrant-exec` | Wraps `vagrant` with structured output / optional wait-for-info behavior used by the vagrant-vbox bastion recipe |
| `vboxmanage-exec` | Wraps `VBoxManage`, including safe shutdown handling before disk attach/detach operations |

## Layout

```
libs/shared/app/golang/
├── cmd/
│   ├── system-env/
│   ├── vagrant-exec/
│   └── vboxmanage-exec/
├── internal/          # shared version, DNS, and platform helpers
├── go.mod
└── README.md
```

Module path: `github.com/novassist-ai/mycs-node/libs/shared/app/golang`

## Build

From the repository root (or via the node-builder script):

```bash
# Development build for the host OS/arch → .build/bin/
./apps/clients/node-builder/scripts/build-utils.sh :dev:clean-all:

# Release-style build for a specific OS/arch → .build/releases/
./apps/clients/node-builder/scripts/build-utils.sh :release:clean-all: linux amd64
```

Artifacts:

- Per-platform directory: `.build/releases/<os>_<arch>/`
- Zip: `.build/releases/mycs-cookbook-utils_<os>_<arch>.zip`
- Host symlink: `.build/bin` → current host build directory

Recipe directories under `cloud/cookbook/recipes/` symlink these binaries from `.build/bin` so Terraform can find them next to the module (`path.module`).

## Development notes

- Go `1.20+` required.
- Behavior is intentionally unchanged from the former spacenode-cookbook utils; prefer fixing bugs in place over redesigning the JSON contracts recipes depend on.
- Version and build timestamp are injected via `-ldflags` into `internal.Version` and `internal.BuildTimestamp`.
