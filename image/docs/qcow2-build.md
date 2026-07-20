# QCOW2 (KVM) MyCS Node Image Build

Standalone Packer + QEMU build that produces a **qcow2** disk image for
KVM-backed clouds (OpenStack, CloudStack, Proxmox, etc.).

Hyperscaler pipelines (**AWS / Azure / GCE**) stay on their existing Packer
builders and are **not** fed from this artifact.

OVH’s existing in-cloud OpenStack Packer path (`build-ovh-image.sh`) is
**unchanged**. This track is additive.

---

## Architecture confirmation

| Host | Target | Acceleration | Supported by default? |
|------|--------|--------------|------------------------|
| amd64 Linux + `/dev/kvm` | amd64 | KVM | Yes |
| arm64 Linux + `/dev/kvm` | arm64 | KVM | Yes |
| Apple Silicon macOS | arm64 | HVF | Yes |
| Intel macOS | amd64 | HVF | Yes |
| Any host | Other arch | TCG (emulation) | Only with `QCOW2_ALLOW_TCG=1` (slow) |

**Yes:** building on amd64 or arm64 hardware/VMs produces a guest image for
**that same architecture** by default (`uname -m`). Pass an explicit arch as
the second argument only when you intend a matching or (rarely) TCG build.

---

## Artifacts

| Path | Description |
|------|-------------|
| `image/.build/qcow2/mycs-node-image_<ver>.qcow2` | Final disk image |
| `image/.build/qcow2/cache/` | Cached Ubuntu cloud base images |
| `image/.build/qcow2/seed/` | Ephemeral cloud-init seed inputs |
| `image/.download/` | mycs-node zip + version (same as other builds) |
| `./build-qcow2-<arch>.log` | Build log in the cwd |

---

## macOS development setup (recommended)

UTM is excellent for **interactive** Linux VMs, but Packer talks to **QEMU
directly**. On a Mac, the most effective Phase‑1 workflow is:

### Option A — Native macOS (preferred for Apple Silicon → arm64)

```bash
brew install packer qemu xorriso jq gh
# Authenticate GitHub CLI for release downloads:
gh auth login
```

On Apple Silicon, Packer needs both EFI **code** and **vars** firmware files
from Homebrew QEMU (`edk2-aarch64-code.fd` + `edk2-arm-vars.fd`). The build
script locates these automatically after `brew install qemu`.

Then from `mycs-node/image`:

```bash
./build/build-qcow2-image.sh dev
# → builds arm64 qcow2 on Apple Silicon (HVF)
```

Optional knobs:

| Variable | Default | Meaning |
|----------|---------|---------|
| `QCOW2_MEMORY` | `8192` | Guest RAM (MiB) |
| `QCOW2_CPUS` | `4` | Guest vCPUs |
| `QCOW2_DISK_SIZE` | `25600M` | Disk size passed to Packer |
| `QCOW2_HEADLESS` | `true` | Set `false` to debug console |
| `UBUNTU_RELEASE` | `resolute` | Ubuntu cloud-image series (26.04; matches AWS / PowerDNS repos) |
| `IS_DEV_BUILD` | `yes` | Download mycs-node zip via `gh` |

### Option B — UTM Linux VM (best when you need Linux/KVM or amd64 elsewhere)

Use UTM when:

- You want a Linux environment that mirrors CI (`/dev/kvm`), or
- You need an **amd64** qcow2 but only have Apple Silicon (run an **x86_64
  Linux VM under UTM** — this is emulated and slower — or use a remote amd64
  builder).

Suggested UTM guest:

1. Create an **Ubuntu 24.04 ARM** VM on Apple Silicon (Virtualization backend).
2. Enable nested virtualization if UTM offers it for that guest (helps KVM).
3. Inside the guest:

```bash
sudo apt-get update
sudo apt-get install -y qemu-system-x86 qemu-system-arm qemu-utils qemu-efi-aarch64 \
  packer xorriso jq curl git
# Install gh from GitHub’s apt repo or download a release binary.
# Ensure your user can access /dev/kvm (group `kvm`).
```

4. Clone `mycs-node`, `cd image`, run `./build/build-qcow2-image.sh dev`.

**Do not** expect Packer’s qemu builder to drive the UTM GUI; UTM is the place
you run Linux+tooling, or a place to **boot-test** the finished `.qcow2`.

### Boot-testing a built image in UTM

1. UTM → New → Emulate/Virtualize → Import the `.qcow2` as a drive (virtio).
2. Attach a small cloud-init seed ISO (`user-data` + `meta-data`, volume label
   `cidata`) if you need SSH/login, or use UTM’s serial console.
3. Confirm cloud-init completes and `/usr/local/lib/cloud-inceptor/` is present.

---

## Usage

```bash
cd image
./build/build-qcow2-image.sh [IMAGE_VERSION] [ARCH]

# Examples
./build/build-qcow2-image.sh dev              # host arch
./build/build-qcow2-image.sh 0.1.0 arm64      # explicit arm64
./build/build-qcow2-image.sh 0.1.0 amd64      # explicit amd64 (must match host unless TCG)
```

Packer template: `packer/build-qcow2.pkr.hcl`  
Wrapper: `build/build-qcow2-image.sh`

The script:

1. Detects host OS/arch and selects QEMU binary + accelerator (HVF/KVM/TCG).
2. Downloads Ubuntu `{resolute}-server-cloudimg-{arch}.img` into `.build/qcow2/cache/`.
3. Builds NoCloud `user-data` / `meta-data` (Packer attaches them via `cd_files`;
   `xorriso` on PATH avoids macOS HFS seed ISOs that cloud-init ignores).
4. Runs the same provisioners as other clouds (`install_packages`).
5. Writes `mycs-node-image_<version>.qcow2`.

**Do not** pass custom `qemuargs` that replace Packer’s defaults — that drops the
boot disk and EFI firmware and SSH will hang forever.

---

## Phase 1.5 — CI publish to S3

Jobs `build-qcow2-image` in:

- `.github/workflows/build-image-dev.yml` (branch `dev`)
- `.github/workflows/build-image-prod.yml` (branch `main`)

### Matrix

| Arch | Runner |
|------|--------|
| `amd64` | `ubuntu-24.04` |
| `arm64` | `ubuntu-24.04-arm` |

### S3 layout (`novassist-public`)

Credentials: `DEV_AWS_ACCESS_KEY_ID` / `DEV_AWS_SECRET_ACCESS_KEY` (dev **and** prod uploads).

```
s3://novassist-public/mycs-releases/mycs-node/image/<channel>/<arch>/mycs-node-image_<VERSION>.qcow2
s3://novassist-public/mycs-releases/mycs-node/image/<channel>/<arch>/mycs-node-image.qcow2
```

- `<channel>` is `dev` or `prod`.
- `<arch>` keeps both architectures from colliding while preserving the
  `mycs-node-image_<VERSION>.qcow2` object name.
- `mycs-node-image.qcow2` is a **0-byte** placeholder with
  `x-amz-website-redirect-location` pointing at the versioned object
  (website-style “latest” URL).

### Scripts

| Script | Role |
|--------|------|
| `build/build-qcow2-image.sh` | Local / CI Packer build |
| `build/publish-qcow2-image.sh <ver> <arch> <channel>` | Upload versioned object + latest redirect |
| `build/delete-qcow2-images.sh [--all] <channel> [arch]` | List (default) or delete (`--all`) |

**Dev CI** runs `delete-qcow2-images.sh --all dev <arch>` before each arch upload
so prior versions for that arch are removed. **Prod** does not delete prior
versions (history accumulates); `--all` remains available for manual cleanup.

## GitHub Actions notes

On hosted Linux runners, enable nested KVM with GitHub’s udev rule (mode `0666`
on `/dev/kvm`), then smoke-test `qemu-system-* -accel kvm` before Packer. If the
smoke test fails, workflows set `QCOW2_ALLOW_TCG=1`. CI also caps guest RAM/CPUs
(`QCOW2_MEMORY=4096`, `QCOW2_CPUS=2`) and sets `PACKER_LOG=1` so a failed QEMU
launch prints qemu stderr in the job log.

### Local publish example

```bash
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...
./build/build-qcow2-image.sh 0.1.0 arm64
./build/publish-qcow2-image.sh 0.1.0 arm64 dev
```

---

## Out of scope

- Changing `build-ovh-image.sh` or OpenStack Packer templates for cutover
- Publishing qcow2 to AWS / Azure / GCE
- Automatic CloudStack/OpenStack upload from S3 (later phase)
