#!/bin/bash

export AWS_PAGER=

LOG_DIR=$(pwd)
BUILD_DIR=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)
AWS_REGION=${AWS_DEFAULT_REGION:-us-east-1}
REGION_SHORT_NAME=$(echo "$AWS_REGION" | tr -d '-')
# shellcheck source=../scripts/ovh/common.sh
source "$BUILD_DIR/scripts/ovh/common.sh"

which openstack >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR! The OpenStack CLI needs to be installed. (https://docs.openstack.org/python-openstackclient/)"
  exit 1
fi

which packer >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR! Packer needs to be installed. (https://www.packer.io/downloads)"
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

which aws >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR! The AWS CLI is required to download MyCloudSpace node artifacts and API keys."
  exit 1
fi

ovh::validate_auth

# MyCloudSpace node service
MYCS_NODE_VER=latest
OSARCH=amd64

IS_DEV_BUILD=${IS_DEV_BUILD:-yes}
if [[ $IS_DEV_BUILD == yes ]]; then
  MYCS_ENV=${MYCS_ENV:-dev}
else
  MYCS_ENV=${MYCS_ENV:-prod}
fi

IMAGE_VERSION=${1:-dev}
IMAGE_NAME=$(ovh::image_name_for_version "$IMAGE_VERSION")
BUILD_REGION=${2:-$OS_REGION_NAME}
export OS_REGION_NAME="$BUILD_REGION"

set -euo pipefail

function ovh::delete_image() {
  local image_name=$1
  local ids

  ids=$(openstack image list --name "$image_name" -f value -c ID)
  for id in $ids; do
    echo "Deleting image '${image_name}' (${id}) in region '${OS_REGION_NAME}'..."
    openstack image delete "$id"
  done
}

function ovh::build_image() {
  local packer_manifest=$1

  ovh::resolve_openstack_ids

  echo "Building image '${IMAGE_NAME}' in region '${OS_REGION_NAME}'..."
  echo "  source image: ${OVH_SOURCE_IMAGE_NAME:-Ubuntu 24.04} (${OVH_SOURCE_IMAGE_ID})"
  echo "  flavor:       ${OVH_BUILD_FLAVOR:-d2-2} (${OVH_FLAVOR_ID})"
  echo "  network:      ${OVH_PUBLIC_NETWORK_NAME:-Ext-Net} (${OVH_NETWORK_ID})"

  cd "$(dirname "$packer_manifest")"
  packer init "$(basename "$packer_manifest")"
  packer build \
    -var "build_dir=${BUILD_DIR}" \
    -var "image_name=${IMAGE_NAME}" \
    -var "image_version=${IMAGE_VERSION}" \
    -var "region=${OS_REGION_NAME}" \
    -var "tenant_id=${OVH_TENANT_ID}" \
    -var "source_image_id=${OVH_SOURCE_IMAGE_ID}" \
    -var "flavor_id=${OVH_FLAVOR_ID}" \
    -var "network_id=${OVH_NETWORK_ID}" \
    "$(basename "$packer_manifest")"
  cd -
}

# download mycloudspace-service release
rm -fr "$BUILD_DIR/.download"
mkdir -p "$BUILD_DIR/.download"
echo -n "${IMAGE_VERSION}" > "$BUILD_DIR/.download/version"

# Download mycs-node-service release
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

# download mycloudspace api public key
# public_keys=$(aws --region "$AWS_REGION" \
#   dynamodb query \
#   --table-name "mycs${MYCS_ENV}-${REGION_SHORT_NAME}_AppConfig" \
#   --key-condition-expression "#keyName = :key" \
#   --expression-attribute-names '{"#keyName":"key"}' \
#   --expression-attribute-values '{":key":{"S":"appKey"}}' \
#   --no-scan-index-forward)
# id=$(echo "$public_keys" | jq -r '.Items[0].id.S')
# public_key=$(echo "$public_keys" | jq -r --arg id "$id" '.Items[] | select(.id.S == $id) | .publicKey.S')
# echo "$public_key" > "$BUILD_DIR/.download/mycs-key-${id}.pem"
echo "" > "$BUILD_DIR/.download/mycs-key-00000.pem"

echo "Building OVHcloud image '${IMAGE_NAME}' in region '${BUILD_REGION}'."
set +e
ovh::delete_image "$IMAGE_NAME"
set -e

ovh::build_image "$BUILD_DIR/packer/build-openstack.pkr.hcl" 2>&1 \
  | tee "$LOG_DIR/build-ovh-${BUILD_REGION}.log"

echo "Image '${IMAGE_NAME}' is available in region '${BUILD_REGION}'."
openstack image show "$IMAGE_NAME" -f yaml
