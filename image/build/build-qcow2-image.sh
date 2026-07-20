#!/bin/bash
#
# Build a MyCS node qcow2 disk image with Packer + QEMU (KVM on Linux, HVF on macOS).
#
# Target architecture defaults to the host architecture (amd64 or arm64). Cross-arch
# builds require software emulation (TCG) and must set QCOW2_ALLOW_TCG=1.
#
# USAGE:
#   ./build/build-qcow2-image.sh [IMAGE_VERSION] [ARCH]
#
# EXAMPLES:
#   ./build/build-qcow2-image.sh dev
#   ./build/build-qcow2-image.sh 0.1.0 arm64
#   QCOW2_MEMORY=4096 QCOW2_CPUS=2 ./build/build-qcow2-image.sh D.260720120000
#
# Artifacts:
#   image/.build/qcow2/<image_name>/<image_name>   (Packer output; renamed to .qcow2)
#

LOG_DIR=$(pwd)
BUILD_DIR=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)

which packer >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR! Packer needs to be installed. (https://www.packer.io/downloads)"
  exit 1
fi

which qemu-img >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR! qemu-img needs to be installed (QEMU). On macOS: brew install qemu"
  exit 1
fi

which gh >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR! The Github CLI needs to be installed and available via the system path. (https://cli.github.com/)"
  exit 1
fi

which jq >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR! The JQ CLI needs to be available in the system path. (https://stedolan.github.io/jq/download/)"
  exit 1
fi

which ssh-keygen >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR! ssh-keygen is required to create a temporary cloud-init SSH key."
  exit 1
fi

# Prefer xorriso for a portable ISO9660 cloud-init seed (works on macOS + Linux).
SEED_ISO_TOOL=""
if which xorriso >/dev/null 2>&1; then
  SEED_ISO_TOOL=xorriso
elif which genisoimage >/dev/null 2>&1; then
  SEED_ISO_TOOL=genisoimage
elif which mkisofs >/dev/null 2>&1; then
  SEED_ISO_TOOL=mkisofs
else
  echo "ERROR! Need xorriso, genisoimage, or mkisofs to create the cloud-init seed ISO."
  echo "  macOS: brew install xorriso"
  echo "  Debian/Ubuntu: apt-get install -y xorriso"
  exit 1
fi

UBUNTU_RELEASE=${UBUNTU_RELEASE:-resolute}
MYCS_NODE_VER=${MYCS_NODE_VER:-latest}

IS_DEV_BUILD=${IS_DEV_BUILD:-yes}
if [[ $IS_DEV_BUILD == yes ]]; then
  MYCS_ENV=${MYCS_ENV:-dev}
else
  MYCS_ENV=${MYCS_ENV:-prod}
fi

IMAGE_VERSION=${1:-dev}

HOST_UNAME=$(uname -s)
HOST_MACHINE=$(uname -m)
case "$HOST_MACHINE" in
  x86_64|amd64) HOST_ARCH=amd64 ;;
  aarch64|arm64) HOST_ARCH=arm64 ;;
  *)
    echo "ERROR! Unsupported host architecture '${HOST_MACHINE}'."
    exit 1
    ;;
esac

TARGET_ARCH=${2:-${QCOW2_ARCH:-$HOST_ARCH}}
case "$TARGET_ARCH" in
  amd64|arm64) ;;
  x86_64) TARGET_ARCH=amd64 ;;
  aarch64) TARGET_ARCH=arm64 ;;
  *)
    echo "ERROR! Unsupported target architecture '${TARGET_ARCH}'. Use amd64 or arm64."
    exit 1
    ;;
esac

# Zip artifact naming matches other build scripts (linux_amd64 / linux_arm64).
OSARCH=$TARGET_ARCH

IMAGE_NAME="mycs-node-image_${IMAGE_VERSION}"
WORK_ROOT="$BUILD_DIR/.build/qcow2"
OUT_DIR="$WORK_ROOT/${IMAGE_NAME}"
CACHE_DIR="$WORK_ROOT/cache"
SEED_DIR="$WORK_ROOT/seed"
SSH_DIR="$WORK_ROOT/ssh"
SEED_ISO="$SEED_DIR/cidata.iso"
SSH_KEY="$SSH_DIR/packer_id_ed25519"
PACKER_MANIFEST="$BUILD_DIR/packer/build-qcow2.pkr.hcl"

QCOW2_MEMORY=${QCOW2_MEMORY:-8192}
QCOW2_CPUS=${QCOW2_CPUS:-4}
QCOW2_DISK_SIZE=${QCOW2_DISK_SIZE:-25600M}
QCOW2_HEADLESS=${QCOW2_HEADLESS:-true}
QCOW2_ALLOW_TCG=${QCOW2_ALLOW_TCG:-0}

set -euo pipefail

function qcow2::iso_tool_create() {
  local out=$1
  local src_dir=$2
  case "$SEED_ISO_TOOL" in
    xorriso)
      # Uppercase volid satisfies ISO 9660; cloud-init accepts CIDATA/cidata.
      xorriso -as mkisofs -V CIDATA -J -R -o "$out" "$src_dir"
      ;;
    genisoimage|mkisofs)
      "$SEED_ISO_TOOL" -output "$out" -volid CIDATA -joliet -rock "$src_dir"
      ;;
  esac
}

function qcow2::prepare_seed() {
  mkdir -p "$SEED_DIR" "$SSH_DIR"
  rm -f "$SSH_KEY" "${SSH_KEY}.pub" "$SEED_ISO"

  ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C "packer-qcow2-${IMAGE_VERSION}" >/dev/null

  local pubkey
  pubkey=$(cat "${SSH_KEY}.pub")

  cat > "$SEED_DIR/meta-data" <<EOF
instance-id: mycs-qcow2-${IMAGE_VERSION}
local-hostname: mycs-node-builder
EOF

  cat > "$SEED_DIR/user-data" <<EOF
#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ${pubkey}
ssh_pwauth: false
package_update: false
package_upgrade: false
EOF

  # Optional local ISO for debugging (Packer attaches user-data/meta-data via cd_files).
  local stage
  stage=$(mktemp -d)
  cp "$SEED_DIR/user-data" "$SEED_DIR/meta-data" "$stage/"
  qcow2::iso_tool_create "$SEED_ISO" "$stage"
  rm -rf "$stage"
}

function qcow2::find_efi_firmware() {
  # Prints: <code.fd> <vars.fd>
  local arch=$1
  local code_candidates=()
  local vars_candidates=()
  if [[ $arch == arm64 ]]; then
    code_candidates=(
      "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
      "/usr/local/share/qemu/edk2-aarch64-code.fd"
      "/usr/share/AAVMF/AAVMF_CODE.fd"
      "/usr/share/qemu/edk2-aarch64-code.fd"
    )
    # Homebrew ships edk2-arm-vars.fd for aarch64; Linux AAVMF has a paired VARS file.
    vars_candidates=(
      "/opt/homebrew/share/qemu/edk2-arm-vars.fd"
      "/usr/local/share/qemu/edk2-arm-vars.fd"
      "/usr/share/AAVMF/AAVMF_VARS.fd"
      "/usr/share/qemu/edk2-arm-vars.fd"
    )
  else
    code_candidates=(
      "/opt/homebrew/share/qemu/edk2-x86_64-code.fd"
      "/usr/local/share/qemu/edk2-x86_64-code.fd"
      "/usr/share/OVMF/OVMF_CODE.fd"
      "/usr/share/qemu/edk2-x86_64-code.fd"
    )
    vars_candidates=(
      "/opt/homebrew/share/qemu/edk2-i386-vars.fd"
      "/usr/local/share/qemu/edk2-i386-vars.fd"
      "/usr/share/OVMF/OVMF_VARS.fd"
      "/usr/share/qemu/edk2-i386-vars.fd"
    )
  fi
  local code="" vars="" path
  for path in "${code_candidates[@]}"; do
    if [[ -f "$path" ]]; then
      code=$path
      break
    fi
  done
  for path in "${vars_candidates[@]}"; do
    if [[ -f "$path" ]]; then
      vars=$path
      break
    fi
  done
  if [[ -z "$code" || -z "$vars" ]]; then
    return 1
  fi
  echo "$code $vars"
}

function qcow2::resolve_platform() {
  local accel qemu_bin machine efi_boot efi_fw efi_vars display_default cpu_model

  if [[ $TARGET_ARCH == arm64 ]]; then
    qemu_bin=qemu-system-aarch64
    machine="virt,gic-version=max"
    efi_boot=true
  else
    qemu_bin=qemu-system-x86_64
    machine=q35
    # Ubuntu cloud images boot with SeaBIOS on x86_64; EFI optional.
    efi_boot=false
  fi

  if ! which "$qemu_bin" >/dev/null 2>&1; then
    echo "ERROR! '${qemu_bin}' not found. Install QEMU (macOS: brew install qemu)."
    exit 1
  fi

  display_default=false
  cpu_model=host
  if [[ $TARGET_ARCH == "$HOST_ARCH" ]]; then
    if [[ $HOST_UNAME == Darwin ]]; then
      accel=hvf
      display_default=true
    elif [[ -r /dev/kvm && -w /dev/kvm ]]; then
      accel=kvm
    elif [[ $QCOW2_ALLOW_TCG == 1 ]]; then
      accel=tcg
      cpu_model=max
      if [[ -e /dev/kvm ]]; then
        echo "WARNING: /dev/kvm exists but is not usable by $(id -un); using TCG."
      else
        echo "WARNING: /dev/kvm not present; using TCG software emulation (slow)."
      fi
    elif [[ -e /dev/kvm ]]; then
      echo "ERROR! /dev/kvm exists but is not readable/writable by $(id -un)."
      echo "  Fix with: sudo chmod 666 /dev/kvm   (or add your user to group 'kvm')"
      echo "  Or set QCOW2_ALLOW_TCG=1 to force slow software emulation."
      exit 1
    else
      echo "ERROR! Native arch build requires /dev/kvm on Linux (or HVF on macOS)."
      echo "Set QCOW2_ALLOW_TCG=1 to force slow software emulation."
      exit 1
    fi
  else
    if [[ $QCOW2_ALLOW_TCG != 1 ]]; then
      echo "ERROR! Cross-arch build requested (host=${HOST_ARCH}, target=${TARGET_ARCH})."
      echo "Native acceleration cannot be used. Re-run with QCOW2_ALLOW_TCG=1 (slow),"
      echo "or build on ${TARGET_ARCH} hardware / a matching UTM Linux VM."
      exit 1
    fi
    accel=tcg
    cpu_model=max
    echo "WARNING: Using TCG software emulation for ${TARGET_ARCH} on ${HOST_ARCH} (slow)."
  fi

  efi_fw=""
  efi_vars=""
  if [[ $efi_boot == true ]]; then
    local efi_pair
    if ! efi_pair=$(qcow2::find_efi_firmware "$TARGET_ARCH"); then
      echo "ERROR! EFI firmware code/vars for ${TARGET_ARCH} not found (edk2/AAVMF)."
      echo "  macOS: brew install qemu"
      echo "  Debian/Ubuntu: apt-get install -y qemu-system-arm qemu-efi-aarch64"
      exit 1
    fi
    efi_fw=${efi_pair%% *}
    efi_vars=${efi_pair#* }
  fi

  export QCOW2_ACCEL=$accel
  export QCOW2_QEMU_BIN=$qemu_bin
  export QCOW2_MACHINE=$machine
  export QCOW2_CPU_MODEL=$cpu_model
  export QCOW2_EFI_BOOT=$efi_boot
  export QCOW2_EFI_FW=$efi_fw
  export QCOW2_EFI_VARS=$efi_vars
  export QCOW2_USE_DEFAULT_DISPLAY=$display_default
}

function qcow2::download_base_image() {
  mkdir -p "$CACHE_DIR"
  local img_name="${UBUNTU_RELEASE}-server-cloudimg-${TARGET_ARCH}.img"
  local img_path="$CACHE_DIR/$img_name"
  local img_url="https://cloud-images.ubuntu.com/${UBUNTU_RELEASE}/current/${img_name}"
  local sums_url="https://cloud-images.ubuntu.com/${UBUNTU_RELEASE}/current/SHA256SUMS"

  if [[ ! -f "$img_path" ]]; then
    echo "Downloading Ubuntu ${UBUNTU_RELEASE} cloud image (${TARGET_ARCH})..."
    curl -fL --retry 3 -o "$img_path" "$img_url"
  else
    echo "Using cached base image: $img_path"
  fi

  export QCOW2_ISO_URL=$img_url
  # Packer resolves the matching line from SHA256SUMS for the basename of iso_url.
  export QCOW2_ISO_CHECKSUM="file:${sums_url}"
  # Local file path for packer (faster / offline after first download).
  export QCOW2_ISO_FILE=$img_path
}

function qcow2::build() {
  qcow2::resolve_platform
  qcow2::download_base_image
  qcow2::prepare_seed

  # Packer creates output_directory itself and errors if it already exists.
  rm -rf "$OUT_DIR"
  mkdir -p "$WORK_ROOT"

  echo "Building qcow2 image '${IMAGE_NAME}'"
  echo "  host:        ${HOST_UNAME}/${HOST_ARCH}"
  echo "  target arch: ${TARGET_ARCH}"
  echo "  accelerator: ${QCOW2_ACCEL}"
  echo "  qemu:        ${QCOW2_QEMU_BIN}"
  echo "  machine:     ${QCOW2_MACHINE}"
  echo "  base image:  ${QCOW2_ISO_FILE}"
  echo "  output:      ${OUT_DIR}"

  cd "$(dirname "$PACKER_MANIFEST")"
  packer init "$(basename "$PACKER_MANIFEST")"
  if ! packer build \
    -var "build_dir=${BUILD_DIR}" \
    -var "image_name=${IMAGE_NAME}" \
    -var "image_version=${IMAGE_VERSION}" \
    -var "iso_url=${QCOW2_ISO_FILE}" \
    -var "iso_checksum=none" \
    -var "output_directory=${OUT_DIR}" \
    -var "qemu_binary=${QCOW2_QEMU_BIN}" \
    -var "accelerator=${QCOW2_ACCEL}" \
    -var "machine_type=${QCOW2_MACHINE}" \
    -var "cpu_model=${QCOW2_CPU_MODEL}" \
    -var "efi_boot=${QCOW2_EFI_BOOT}" \
    -var "efi_firmware_code=${QCOW2_EFI_FW}" \
    -var "efi_firmware_vars=${QCOW2_EFI_VARS}" \
    -var "ssh_private_key_file=${SSH_KEY}" \
    -var "seed_dir=${SEED_DIR}" \
    -var "memory=${QCOW2_MEMORY}" \
    -var "cpus=${QCOW2_CPUS}" \
    -var "disk_size=${QCOW2_DISK_SIZE}" \
    -var "headless=${QCOW2_HEADLESS}" \
    -var "use_default_display=${QCOW2_USE_DEFAULT_DISPLAY}" \
    "$(basename "$PACKER_MANIFEST")"
  then
    cd - >/dev/null
    echo "ERROR! packer build failed."
    exit 1
  fi
  cd - >/dev/null

  # Packer writes the disk as vm_name without a guaranteed .qcow2 suffix.
  local artifact=""
  if [[ -f "$OUT_DIR/${IMAGE_NAME}" ]]; then
    artifact="$OUT_DIR/${IMAGE_NAME}"
  elif [[ -f "$OUT_DIR/${IMAGE_NAME}.qcow2" ]]; then
    artifact="$OUT_DIR/${IMAGE_NAME}.qcow2"
  else
    artifact=$(find "$OUT_DIR" -maxdepth 1 -type f \( -name '*.qcow2' -o -name "${IMAGE_NAME}*" \) | head -1)
  fi

  if [[ -z "$artifact" || ! -f "$artifact" ]]; then
    echo "ERROR! Packer finished but no qcow2 artifact was found under ${OUT_DIR}."
    exit 1
  fi

  local final="$WORK_ROOT/${IMAGE_NAME}.qcow2"
  if [[ "$artifact" != "$final" ]]; then
    mv -f "$artifact" "$final"
  fi
  # Keep Packer work dir for debugging; primary artifact is the flat .qcow2 path.
  echo "Built: $final"
  qemu-img info "$final"
}

# Prepare mycs-node service download (shared with other cloud builds).
rm -fr "$BUILD_DIR/.download"
mkdir -p "$BUILD_DIR/.download" "$WORK_ROOT"
echo -n "${IMAGE_VERSION}" > "$BUILD_DIR/.download/version"

MYCS_NODE_RELEASE_REPO=${MYCS_NODE_RELEASE_REPO:-novassist-ai/mycs-node}
if [[ $IS_DEV_BUILD == yes ]]; then
  gh release download --clobber \
    --pattern "mycs-node-service_linux_${OSARCH}.zip" \
    --repo "$MYCS_NODE_RELEASE_REPO" \
    --dir "$BUILD_DIR/.download"
elif [[ $MYCS_NODE_VER == latest ]]; then
  gh release download --clobber \
    --pattern "mycs-node-service_linux_${OSARCH}.zip" \
    --repo "$MYCS_NODE_RELEASE_REPO" \
    --dir "$BUILD_DIR/.download"
else
  gh release download "$MYCS_NODE_VER" --clobber \
    --pattern "mycs-node-service_linux_${OSARCH}.zip" \
    --repo "$MYCS_NODE_RELEASE_REPO" \
    --dir "$BUILD_DIR/.download"
fi

# Placeholder API key (same pattern as OVH/Vagrant local builds).
echo "" > "$BUILD_DIR/.download/mycs-key-00000.pem"

echo "Building qcow2 MyCS node image '${IMAGE_NAME}' (${TARGET_ARCH})."
set +e
qcow2::build 2>&1 | tee "$LOG_DIR/build-qcow2-${TARGET_ARCH}.log"
status=${PIPESTATUS[0]}
exit "$status"
