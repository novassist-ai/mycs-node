#!/bin/bash
# Resolve the MyCS bastion image name for node-builder Docker builds.
#
# Usage:
#   ./apps/clients/node-builder/scripts/get-cloud-image.sh       # local CLI → mycs-bastion_dev
#   ./apps/clients/node-builder/scripts/get-cloud-image.sh dev   # local CLI → mycs-bastion_dev
#   ./apps/clients/node-builder/scripts/get-cloud-image.sh ci    # latest GH Actions D.* AMI
#   ./apps/clients/node-builder/scripts/get-cloud-image.sh prod  # latest mycs-bastion_X.Y.Z
#
# Requires AWS CLI credentials with ec2:DescribeImages (us-east-1) for ci/prod.

set -euo pipefail

mode=${1:-dev}

case "${mode}" in
  dev)
    echo "mycs-bastion_dev"
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
  --filters "Name=name,Values=mycs-bastion_*")

if [[ "${mode}" == "ci" ]]; then
  # GH Actions bastion builds use mycs-bastion_D.YYMMDDHHMMSS
  name=$(echo "$images" | jq -r '
    [.Images[] | select(.Name | test("^mycs-bastion_D\\.[0-9]+$"))]
    | sort_by(.CreationDate)[-1].Name // empty
  ')
  if [[ -z "${name}" ]]; then
    echo "ERROR: No CI bastion image found (expected mycs-bastion_D.*)." >&2
    exit 1
  fi
  echo "${name}"
  exit 0
fi

prod_images=$(echo "$images" | jq '[.Images[] | select(.Name|test("^mycs-bastion_[0-9]+\\.[0-9]+\\.[0-9]+$"))]')
name=$(echo "$prod_images" | jq -r 'sort_by(.Name | split("_")[1] | split(".") | map(tonumber))[-1] | .Name')

if [[ -z "${name}" || "${name}" == "null" ]]; then
  echo "ERROR: No production mycs-bastion image found (expected mycs-bastion_X.Y.Z)." >&2
  exit 1
fi

echo "${name}"
