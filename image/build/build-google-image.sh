#!/bin/bash

LOG_DIR=$(pwd)
BUILD_DIR=$(cd $(dirname $BASH_SOURCE)/.. && pwd)

which gcloud >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  "ERROR! The Google SDK CLI needs to be installed and configured. (https://cloud.google.com/sdk/)"
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

if [[ ! -e $GOOGLE_CREDENTIALS ]]; then
  "ERROR! Invalid Google service account key file path in the GOOGLE_CREDENTIALS environment variable"
  exit 1
fi

# Source image to build from 
SOURCE_IMAGE_FAMILY=ubuntu-2204-lts

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
IMAGE_NAME="mycs-bastion"
PUBLISH_IMAGE_NAME="${IMAGE_NAME}_${IMAGE_VERSION}"
IMAGE_NAME="${IMAGE_NAME}-$(echo "${IMAGE_VERSION}" | tr '.' '-' | tr '[:upper:]' '[:lower:]')"

set -euo pipefail

function google::create_bucket() {

  local bucket_name=$1
  local region=$2

  set +e
  gsutil ls | awk -F'/' '{ print $3 }' | grep "${bucket_name}" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    set -e
    gsutil mb -l $region gs://${bucket_name}
    gsutil iam ch \
      allUsers:objectViewer \
      allAuthenticatedUsers:objectViewer \
      gs://${bucket_name}
  else
    set -e
  fi

  echo -e "Bastion images in '${region}' region will be published to bucket 'gs://${bucket_name}/'."
}

function google::build_image() {

  local region=$1
  local packer_manifest=$2

  local publish_bucket=${GS_PUBLISH_BUCKET_PREFIX:-mycsimages}_${region}
  google::create_bucket "$publish_bucket" "$region"

  set +e
  echo -e "\nDeleting image with name '$IMAGE_NAME'..."
  gcloud compute images list --filter="name=$IMAGE_NAME" | grep "$IMAGE_NAME" >/dev/null 2>&1
  [[ $? -eq 0 ]] && gcloud compute images delete -q "$IMAGE_NAME"
  set -e

  echo -e "\nBuilding image '$IMAGE_NAME' using source image family '$SOURCE_IMAGE_FAMILY'..."
  cd $(dirname $packer_manifest)
  packer init \
    $(basename $packer_manifest)
  packer build \
    -var "build_dir=$BUILD_DIR" \
    -var "source_image_family=$SOURCE_IMAGE_FAMILY" \
    -var "image_name=$IMAGE_NAME" \
    -var "publish_bucket=$publish_bucket" \
    -var "publish_image_name=$PUBLISH_IMAGE_NAME" \
    $(basename $packer_manifest)
  cd -

  set +e
  gsutil rm \
    "gs://${publish_bucket}/logs/${PUBLISH_IMAGE_NAME}.tar.gz.exporter.log" >/dev/null 2>&1
  set -e
  gsutil mv \
    "gs://${publish_bucket}/mycs-bastion/${PUBLISH_IMAGE_NAME}.tar.gz.exporter.log" \
    "gs://${publish_bucket}/logs/${PUBLISH_IMAGE_NAME}.tar.gz.exporter.log"
}

# download mycloudspace-service release
rm -fr $BUILD_DIR/.download
mkdir -p $BUILD_DIR/.download
echo -n "${IMAGE_VERSION}" > $BUILD_DIR/.download/version

MYCS_NODE_RELEASE_REPO=${MYCS_NODE_RELEASE_REPO:-novassist-ai/mycs-node}
if [[ $IS_DEV_BUILD == yes ]]; then
  aws s3 cp s3://mycsdev-deploy-artifacts/releases/mycs-node_linux_${OSARCH}.zip .download
elif [[ $MYCS_NODE_VER == latest ]]; then
  gh release download --clobber --pattern "mycs-node_linux_${OSARCH}.zip" --repo $MYCS_NODE_RELEASE_REPO --dir .download
else
  gh release download $MYCS_NODE_VER --clobber --pattern "mycs-node_linux_${OSARCH}.zip" --repo $MYCS_NODE_RELEASE_REPO --dir .download
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

gcloud auth activate-service-account --key-file=$GOOGLE_CREDENTIALS
gcloud config set account $GOOGLE_ACCOUNT
gcloud config set project --quiet $GOOGLE_PROJECT

echo "Building image."
google::build_image \
  "$GOOGLE_REGION" \
  "$BUILD_DIR/packer/build-google.pkr.hcl" 2>&1 \
  | tee $LOG_DIR/build-google.log
