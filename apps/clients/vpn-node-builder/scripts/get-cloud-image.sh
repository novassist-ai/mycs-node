#!/bin/bash
# Resolve the MyCS bastion/node image name for vpn-node-builder Docker builds.
#
# Usage:
#   ./apps/clients/vpn-node-builder/scripts/get-cloud-image.sh       # local CLI → mycs-node-image_dev
#   ./apps/clients/vpn-node-builder/scripts/get-cloud-image.sh dev   # local CLI → mycs-node-image_dev
#   ./apps/clients/vpn-node-builder/scripts/get-cloud-image.sh ci    # latest GH Actions X.Y.Z-devN AMI
#   ./apps/clients/vpn-node-builder/scripts/get-cloud-image.sh prod  # latest mycs-node-image_X.Y.Z
#
# Requires AWS CLI credentials with ec2:DescribeImages (us-east-1) for ci/prod.

set -euo pipefail

prefix=mycs-node-image
mode=${1:-dev}

case "${mode}" in
  dev)
    echo "${prefix}_dev"
    exit 0
    ;;
  ci|prod)
    ;;
  *)
    echo "Usage: $0 [dev|ci|prod]" >&2
    exit 1
    ;;
esac

images=$(aws ec2 describe-images --output json \
  --region "${AWS_DEFAULT_REGION:-us-east-1}" \
  --owners self \
  --filters "Name=name,Values=${prefix}_*")

if [[ "${mode}" == "ci" ]]; then
  # GH Actions bastion builds use mycs-node-image_X.Y.Z-devN (see generate-version.sh)
  name=$(echo "$images" | jq -r --arg p "${prefix}" '
    [.Images[] | select(.Name | test("^" + $p + "_[0-9]+\\.[0-9]+\\.[0-9]+-dev[0-9]+$"))]
    | sort_by(.CreationDate)[-1].Name // empty
  ')
  if [[ -z "${name}" ]]; then
    echo "ERROR: No CI image found (expected ${prefix}_X.Y.Z-devN)." >&2
    exit 1
  fi
  echo "${name}"
  exit 0
fi

prod_images=$(echo "$images" | jq --arg p "${prefix}" \
  '[.Images[] | select(.Name|test("^" + $p + "_[0-9]+\\.[0-9]+\\.[0-9]+$"))]')
name=$(echo "$prod_images" | jq -r \
  'sort_by(.Name | split("_")[-1] | split(".") | map(tonumber))[-1] | .Name')

if [[ -z "${name}" || "${name}" == "null" ]]; then
  echo "ERROR: No production image found (expected ${prefix}_X.Y.Z)." >&2
  exit 1
fi

echo "${name}"
