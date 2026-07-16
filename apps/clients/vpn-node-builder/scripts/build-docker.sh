#!/bin/bash
# Build the novassist/vpn-node-builder Docker image from the repository root.
#
# Usage:
#   ./apps/clients/vpn-node-builder/scripts/build-docker.sh [--clean|-c] [tag] [env] [version]
#
# Examples:
#   ./apps/clients/vpn-node-builder/scripts/build-docker.sh dev dev
#   ./apps/clients/vpn-node-builder/scripts/build-docker.sh --clean dev dev
#   ./apps/clients/vpn-node-builder/scripts/build-docker.sh latest prod

set -euo pipefail

clean=0
positional=()
for arg in "$@"; do
  case "${arg}" in
    --clean|-c) clean=1 ;;
    *) positional+=("${arg}") ;;
  esac
done

tag=${positional[0]:-dev}
env=${positional[1]:-dev}
version=${positional[2]:-dev}

script_dir=$(cd "$(dirname "$0")" && pwd)
root_dir=$(cd "${script_dir}/../../../.." && pwd)

# Publisher locators for sandbox recipes (required TF_VAR_* with no Terraform default).
# AWS dev vs prod accounts differ; GCS/Azure prefixes currently match publish scripts.
BASTION_IMAGE_BUCKET_PREFIX=${BASTION_IMAGE_BUCKET_PREFIX:-mycsimages}
BASTION_IMAGE_STORAGE_ACCOUNT_PREFIX=${BASTION_IMAGE_STORAGE_ACCOUNT_PREFIX:-mycs}
BASTION_IMAGE_CONTAINER=${BASTION_IMAGE_CONTAINER:-nodeimage}

if [[ "${env}" == "prod" ]]; then
  bastion_image=$("${script_dir}/get-cloud-image.sh" prod)
  version=${VERSION:-${tag}}
  bastion_image_owner=${BASTION_IMAGE_OWNER:-975050267636}
else
  bastion_image=$("${script_dir}/get-cloud-image.sh" dev)
  version=dev
  bastion_image_owner=${BASTION_IMAGE_OWNER:-244289018343}
fi

# Local builds use the same GHCR repository name end users pull via brew.
image="ghcr.io/novassist-ai/vpn-node-builder:${tag}"
build_opts=()
if [[ "${clean}" -eq 1 ]]; then
  build_opts+=(--no-cache --pull)
  echo "Clean rebuild (no cache, pull base image)"
fi

echo "Building ${image} (env=${env}, bastion=${bastion_image}, owner=${bastion_image_owner})..."

# With `set -u`, an empty array expands as unbound; guard with ${arr[@]+...}.
docker build ${build_opts[@]+"${build_opts[@]}"} \
  -f "${root_dir}/apps/clients/vpn-node-builder/Dockerfile" \
  --build-arg "env=${env}" \
  --build-arg "version=${version}" \
  --build-arg "bastion_image_name=${bastion_image}" \
  --build-arg "bastion_image_owner=${bastion_image_owner}" \
  --build-arg "bastion_image_bucket_prefix=${BASTION_IMAGE_BUCKET_PREFIX}" \
  --build-arg "bastion_image_storage_account_prefix=${BASTION_IMAGE_STORAGE_ACCOUNT_PREFIX}" \
  --build-arg "bastion_image_container=${BASTION_IMAGE_CONTAINER}" \
  -t "${image}" \
  "${root_dir}"

echo "Built ${image}"
echo "Smoke: docker run --rm ${image} --version"
