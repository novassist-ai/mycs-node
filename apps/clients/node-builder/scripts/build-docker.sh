#!/bin/bash
# Build the novassist/node-builder Docker image from the repository root.
#
# Usage:
#   ./apps/clients/node-builder/scripts/build-docker.sh [--clean|-c] [tag] [env] [version]
#
# Examples:
#   ./apps/clients/node-builder/scripts/build-docker.sh dev dev
#   ./apps/clients/node-builder/scripts/build-docker.sh --clean dev dev
#   ./apps/clients/node-builder/scripts/build-docker.sh latest prod

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

if [[ "${env}" == "prod" ]]; then
  bastion_image=$("${script_dir}/get-cloud-image.sh" prod)
  version=${VERSION:-${tag}}
else
  bastion_image=$("${script_dir}/get-cloud-image.sh" dev)
  version=dev
fi

image="novassist/node-builder:${tag}"
build_opts=()
if [[ "${clean}" -eq 1 ]]; then
  build_opts+=(--no-cache --pull)
  echo "Clean rebuild (no cache, pull base image)"
fi

echo "Building ${image} (env=${env}, bastion=${bastion_image})..."

docker build "${build_opts[@]}" \
  -f "${root_dir}/apps/clients/node-builder/Dockerfile" \
  --build-arg "env=${env}" \
  --build-arg "version=${version}" \
  --build-arg "bastion_image_name=${bastion_image}" \
  -t "${image}" \
  "${root_dir}"

echo "Built ${image}"
echo "Smoke: docker run --rm ${image} --version"
