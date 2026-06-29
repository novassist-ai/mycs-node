#!/bin/bash

LOG_DIR=$(pwd)
BUILD_DIR=$(cd $(dirname $BASH_SOURCE)/.. && pwd)

which az >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  "ERROR! The Azure SDK CLI needs to be installed and configured. (https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)"
  exit 1
fi

which gh >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  "ERROR! The Github CLI needs to be installed and available via the system path. (https://cli.github.com/)"
  exit 1
fi

which jq >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  "ERROR! The JQ CLI needs to be available in the system path. (https://stedolan.github.io/jq/download/)"
  exit 1
fi

if [[ -z $ARM_SUBSCRIPTION_ID
  || -z $ARM_TENANT_ID
  || -z $ARM_CLIENT_ID
  || -z $ARM_CLIENT_SECRET ]]; then
  "ERROR! Azure environment variables ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, ARM_CLIENT_ID and ARM_CLIENT_SECRET should be set."
  exit 1
fi

az login --service-principal \
  --username "$ARM_CLIENT_ID" \
  --password "$ARM_CLIENT_SECRET" \
  --tenant "$ARM_TENANT_ID"

echo "Logged into Azure..."

# Source image to build from 
SOURCE_IMAGE_PUBLISHER="Canonical"
SOURCE_IMAGE_OFFER="0001-com-ubuntu-server-jammy"
SOURCE_IMAGE_SKU="22_04-lts-gen2"

# MyCloudSpace node service
MYCS_NODE_VER=latest
OSARCH=amd64

IS_DEV_BUILD=${IS_DEV_BUILD:-yes}
if [[ $IS_DEV_BUILD == yes ]]; then
  MYCS_ENV=${MYCS_ENV:-dev}
else
  MYCS_ENV=${MYCS_ENV:-prod}
fi

# Append version to image name
IMAGE_VERSION=${1:-dev}
IMAGE_NAME="appbricks-bastion-${MYCS_ENV}"
IMAGE_DISK_SNAPSHOT_NAME="appbricksbastion"
IMAGE_DISK_SNAPSHOT_NAME="${IMAGE_DISK_SNAPSHOT_NAME}_$(echo ${IMAGE_VERSION} | sed 's/\./_/g')" 

ARM_DEFAULT_RESOURCE_GROUP=${ARM_DEFAULT_RESOURCE_GROUP:-external}
echo "Building image in resource group '$ARM_DEFAULT_RESOURCE_GROUP'."

LOCATION=${2:-$(az group show --name $ARM_DEFAULT_RESOURCE_GROUP | jq -r .location)}

set -euo pipefail

image_publisher=$SOURCE_IMAGE_PUBLISHER
image_offer=$SOURCE_IMAGE_OFFER
image_sku=$SOURCE_IMAGE_SKU
image_version=$(az vm image list --all \
  --publisher "$image_publisher" \
  --offer "$image_offer" \
  --sku "$image_sku" \
  | jq -r 'sort_by(.version) | reverse | first | .version')

# Accept terms if any
# az vm image terms accept --urn "$image_publisher:$image_offer:$image_sku:$image_version"

function azure::build_image() {

  local location=$1
  local packer_manifest=$2

  local image_name="${IMAGE_NAME}_${location}"
  local image_snapshot_name="${IMAGE_DISK_SNAPSHOT_NAME}_${location}"
  echo -e "\nDeleting image with name '$image_name' and its associated snapshot."

  set +e
  resp=$(az image show --name "$image_name" --resource-group "$ARM_DEFAULT_RESOURCE_GROUP" 2>/dev/null) 
  [[ $? -eq 0 ]] && az image delete --ids $(echo "$resp" | jq -r .id)
  resp=$(az snapshot show --name "$image_snapshot_name" --resource-group "$ARM_DEFAULT_RESOURCE_GROUP" 2>/dev/null) 
  [[ $? -eq 0 ]] && az snapshot delete --ids $(echo "$resp" | jq -r .id)
  set -e

  echo -e "\nBuilding image '$image_name' using source image type '$SOURCE_IMAGE_OFFER' from publisher '$SOURCE_IMAGE_PUBLISHER'"
  echo -e "and saving to resource group '$ARM_DEFAULT_RESOURCE_GROUP' in '$location'...\n"
  cd $(dirname $packer_manifest)
  packer init \
    $(basename $packer_manifest)
  packer build \
    -var "build_dir=$BUILD_DIR" \
    -var "image_name=$image_name" \
    -var "image_snapshot_name=$image_snapshot_name" \
    -var "resource_group=$ARM_DEFAULT_RESOURCE_GROUP" \
    -var "location=$location" \
    -var "image_publisher=$image_publisher" \
    -var "image_offer=$image_offer" \
    -var "image_sku=$image_sku" \
    -var "image_version=$image_version" \
    $(basename $packer_manifest)
  cd -
}

# download mycloudspace-service release
rm -fr $BUILD_DIR/.download
mkdir -p $BUILD_DIR/.download
echo -n "${IMAGE_VERSION}" > $BUILD_DIR/.download/version

if [[ $IS_DEV_BUILD == yes ]]; then
  aws s3 cp s3://mycsdev-deploy-artifacts/releases/mycs-node_linux_${OSARCH}.zip .download
elif [[ $MYCS_NODE_VER == latest ]]; then
  gh release download --clobber --pattern "mycs-node_linux_${OSARCH}.zip" --repo appbricks/mycloudspace-node --dir .download
else
  gh release download $MYCS_NODE_VER --clobber --pattern "mycs-node_linux_${OSARCH}.zip" --repo appbricks/mycloudspace-node --dir .download
fi

# download mycloudspace api public key
public_keys=$(aws --region us-east-1 \
  dynamodb query \
  --table-name mycs${MYCS_ENV}_AppConfig \
  --key-condition-expression "#keyName = :key" \
  --expression-attribute-names '{"#keyName":"key"}' \
  --expression-attribute-values '{":key":{"S":"appKey"}}' \
  --no-scan-index-forward)
id=$(echo $public_keys | jq -r '.Items[0].id.S')
public_key=$(echo $public_keys | jq -r --arg id "$id" '.Items[] | select(.id.S == $id) | .publicKey.S')
echo "$public_key" > .download/mycs-key-$id.pem

echo "Building image for location $LOCATION in resource group $ARM_DEFAULT_RESOURCE_GROUP."
azure::build_image "$LOCATION" \
  "$BUILD_DIR/packer/build-azure.pkr.hcl" 2>&1 \
  | tee $LOG_DIR/build-azure-$LOCATION.log
