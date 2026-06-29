#!/bin/bash

LOG_DIR=$(pwd)
BUILD_DIR=$(cd $(dirname $BASH_SOURCE)/.. && pwd)

which vboxmanage >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  "ERROR! Oracle VirtualBox needs to be installed and available via the system path. (https://www.virtualbox.org/wiki/Downloads)"
  exit 1
fi

which vagrant >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  "ERROR! Hashicorp Vagrant needs to be installed and available via the system path. (https://www.virtualbox.org/wiki/Downloads)"
  exit 1
fi

which gh >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  "ERROR! The Github CLI needs to be installed and available via the system path. (https://cli.github.com/)"
  exit 1
fi

which jq >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  "ERROR! The JQ CLI needs to be installed and available via the system path. (https://stedolan.github.io/jq/download/)"
  exit 1
fi

# Source image to build from 
BASE_VAGRANT_IMAGE=ubuntu/jammy64

# MyCloudSpace node service
MYCS_NODE_VER=latest
OSARCH=amd64

IS_DEV_BUILD=${IS_DEV_BUILD:-yes}
if [[ $IS_DEV_BUILD == yes ]]; then
  MYCS_ENV=${MYCS_ENV:-dev}
else
  MYCS_ENV=${MYCS_ENV:-prod}
fi

# image name and version
BOX_NAME="appbricks-bastion"
BOX_VERSION=${1:-0.0.0}
[[ $BOX_VERSION != D.* ]] || \
  BOX_VERSION=0.0.${BOX_VERSION#D.*}

set -euo pipefail

function vagrant::build_box() {
  local box_name=$1
  local box_version=$2
  local packer_manifest=$3

  local existing_ver=$(curl -s "https://app.vagrantup.com/api/v1/box/appbricks/appbricks-bastion/version/${box_version}" \
    --request GET \
    --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
    | jq -r .version)
  if [[ $existing_ver == $box_version ]]; then
    curl -f -s "https://app.vagrantup.com/api/v1/box/appbricks/appbricks-bastion/version/${box_version}" \
      --request DELETE \
      --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
      >/dev/null 2>&1
  fi

  echo -e "\nBuilding vagrant box '$box_name' version '$box_version' using base box iamge '$BASE_VAGRANT_IMAGE'..."
  cd $(dirname $packer_manifest)
  packer init \
    $(basename $packer_manifest)
  packer build \
    -var "build_dir=$BUILD_DIR" \
    -var "name=$box_name" \
    -var "version=$box_version" \
    -var "base_image=$BASE_VAGRANT_IMAGE" \
    $(basename $packer_manifest)
  cd -
}

# download mycloudspace-service release
rm -fr $BUILD_DIR/.build $BUILD_DIR/.download
mkdir -p $BUILD_DIR/.download
echo -n "${BOX_VERSION}" > $BUILD_DIR/.download/version

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

vagrant::build_box "$BOX_NAME" \
  "$BOX_VERSION" \
  "$BUILD_DIR/packer/build-vagrant.pkr.hcl" 2>&1 \
  | tee $LOG_DIR/build-vagrant.log &

# Wait for all parallel jobs to finish
wait