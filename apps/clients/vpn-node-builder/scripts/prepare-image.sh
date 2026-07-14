#!/bin/bash
# Install runtime tooling and pre-init Terraform providers inside the image.
# Invoked from the Dockerfile after the Python CLI and cookbook are copied.

set -euo pipefail

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64)
    tf_arch=amd64
    aws_arch=x86_64
    ;;
  aarch64|arm64)
    tf_arch=arm64
    aws_arch=aarch64
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

export DEBIAN_FRONTEND=noninteractive

# AWS CLI v2 (uses uname-style arch names, not Terraform's amd64/arm64)
tmpdir=$(mktemp -d)
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o "${tmpdir}/awscliv2.zip"
unzip -q "${tmpdir}/awscliv2.zip" -d "${tmpdir}"
"${tmpdir}/aws/install"
rm -rf "${tmpdir}"

# Google Cloud SDK
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
export CLOUDSDK_INSTALL_DIR=/usr/local/lib
curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir="${CLOUDSDK_INSTALL_DIR}"
ln -sf "${CLOUDSDK_INSTALL_DIR}/google-cloud-sdk/bin/gcloud" /usr/local/bin/gcloud
ln -sf "${CLOUDSDK_INSTALL_DIR}/google-cloud-sdk/bin/gsutil" /usr/local/bin/gsutil

# Azure CLI
pip install --no-cache-dir azure-cli

# Terraform
terraform_version=1.5.7
curl -fsSL "https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_${tf_arch}.zip" \
  -o /tmp/terraform.zip
unzip -q /tmp/terraform.zip -d /usr/local/bin
rm -f /tmp/terraform.zip

# Experimental UDP tunnel helpers (parity with legacy cookbook image)
git clone --depth 1 -b branch_libev https://github.com/wangyu-/UDPspeeder.git /tmp/udp-speeder
make -C /tmp/udp-speeder
mv /tmp/udp-speeder/speederv2 /usr/local/bin/udp-speeder

git clone --depth 1 https://github.com/wangyu-/udp2raw-tunnel.git /tmp/udp2raw-tunnel
make -C /tmp/udp2raw-tunnel
mv /tmp/udp2raw-tunnel/udp2raw /usr/local/bin/udp2raw

# KCP tunnel client (xtaci/kcptun releases removed; build from archived mirror)
git clone --depth 1 https://github.com/kongkx/kcptun-archive.git /tmp/kcptun
(
  cd /tmp/kcptun
  go build -mod=vendor -ldflags "-s -w" -o /usr/local/bin/kcptun-client ./client
)

# Provider lock files for embedded recipes (no backend)
cookbook_root=/usr/local/lib/vpn-node-builder/cloud/cookbook/recipes
for rd in "${cookbook_root}"/*/*/; do
  [[ -d "${rd}" ]] || continue
  terraform -chdir="${rd}" init -backend=false -input=false
  rm -rf "${rd}/.terraform"
done

# Link Go utils next to local recipes that expect path.module binaries
for recipe in \
  "${cookbook_root}/sandbox/vagrant-vbox" \
  "${cookbook_root}/approuter/docker"; do
  [[ -d "${recipe}" ]] || continue
  for bin in system-env vagrant-exec vboxmanage-exec; do
    target="${recipe}/${bin}"
    if [[ -L "${target}" || -e "${target}" ]]; then
      rm -f "${target}"
    fi
    ln -sf /usr/local/lib/vpn-node-builder/.build/bin/"${bin}" "${target}"
  done
done

mkdir -p /work
rm -rf /tmp/udp-speeder /tmp/udp2raw-tunnel /tmp/kcptun

# Trim build-only packages
apt-get purge -y build-essential autoconf automake libtool pkg-config \
  && apt-get autoremove -y \
  && rm -rf /var/lib/apt/lists/*
