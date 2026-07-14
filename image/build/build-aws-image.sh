#!/bin/bash

export AWS_PAGER=

LOG_DIR=$(pwd)
BUILD_DIR=$(cd $(dirname $BASH_SOURCE)/.. && pwd)

which aws >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  "ERROR! The AWS CLI needs to be installed and configured. (https://aws.amazon.com/cli/)"
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

# Source image to build from 
UBUNTU_RELEASE=resolute

# MyCloudSpace node service
MYCS_NODE_VER=latest
OSARCH=arm64

IS_DEV_BUILD=${IS_DEV_BUILD:-yes}
if [[ $IS_DEV_BUILD == yes ]]; then
  MYCS_ENV=${MYCS_ENV:-dev}
else
  MYCS_ENV=${MYCS_ENV:-prod}
fi

# Append version to AMI name
IMAGE_VERSION=${2:-dev}
IMAGE_NAME="mycs-node-image_${IMAGE_VERSION}"

set -euo pipefail

function aws::build_ami() {

  local image_name=$1
  local region=$2
  local base_amis=$3
  local packer_manifest=$4

  echo -e "\nDeleting images with name '$image_name' in region $region..."
  local images=$(aws ec2 describe-images --output json \
    --region $region --owner self --filters "Name=name,Values=$image_name")

  for i in $(echo "$images" | jq -r '.Images[].ImageId'); do
  
    s=$(echo -e "$images" | jq -r  '.Images[] 
      | select(.ImageId=="'$i'") 
      | .BlockDeviceMappings[0].Ebs.SnapshotId')

    echo -ne "- Deleting $i with snapshot $s"
    aws ec2 modify-image-attribute \
      --region "$region" \
      --image-id "$i" \
      --launch-permission "Remove=[{Group=all}]"
    aws ec2 deregister-image \
      --region $region \
      --image-id $i
    aws ec2 delete-snapshot \
      --region $region \
      --snapshot-id $s

    while [[ -n "$(aws ec2 describe-images --region $region --owner self | jq -r '.Images[] | select(.ImageId=="'$i'") | .ImageId')" ]]; do
      echo -ne "."
      sleep 2
    done
    echo "...done"
  done
  sleep 10

  local ami=$(echo "$base_amis" | grep "|$region|" | sort -r | head -1 | awk -F'|' '{ print $3 }')

  echo -e "\nBuilding AMI image '$image_name' in region $region using base AMI $ami..."
  cd $(dirname $packer_manifest)
  packer init \
    $(basename $packer_manifest)
  packer build \
    -var "build_dir=$BUILD_DIR" \
    -var "region=$region" \
    -var "ami=$ami" \
    -var "name=$image_name" \
    $(basename $packer_manifest)
  cd -
}

# region for mycloudspace services
AWS_REGION=${AWS_DEFAULT_REGION:-us-east-1}
REGION_SHORT_NAME=$(echo $AWS_REGION | tr -d '-')

# download mycloudspace-service release
rm -fr $BUILD_DIR/.download
mkdir -p $BUILD_DIR/.download
echo -n "${IMAGE_VERSION}" > $BUILD_DIR/.download/version

# MYCS_NODE_RELEASE_REPO=${MYCS_NODE_RELEASE_REPO:-novassist-ai/mycs-node}
# if [[ $IS_DEV_BUILD == yes ]]; then
#   aws s3 cp s3://mycsdev-${REGION_SHORT_NAME}-deploy-artifacts/releases/mycs-node_linux_${OSARCH}.zip .download
# elif [[ $MYCS_NODE_VER == latest ]]; then
#   gh release download --clobber --pattern "mycs-node_linux_${OSARCH}.zip" --repo $MYCS_NODE_RELEASE_REPO --dir .download
# else
#   gh release download $MYCS_NODE_VER --clobber --pattern "mycs-node_linux_${OSARCH}.zip" --repo $MYCS_NODE_RELEASE_REPO --dir .download
# fi

# TODO: remove this
touch $BUILD_DIR/.download/mycs-node_linux_${OSARCH}.zip

# download mycloudspace api public key
# public_keys=$(aws --region us-east-1 \
#   dynamodb query \
#   --table-name mycs${MYCS_ENV}-${REGION_SHORT_NAME}_AppConfig \
#   --key-condition-expression "#keyName = :key" \
#   --expression-attribute-names '{"#keyName":"key"}' \
#   --expression-attribute-values '{":key":{"S":"appKey"}}' \
#   --no-scan-index-forward)
# id=$(echo $public_keys | jq -r '.Items[0].id.S')
# public_key=$(echo $public_keys | jq -r --arg id "$id" '.Items[] | select(.id.S == $id) | .publicKey.S')
# echo "$public_key" > .download/mycs-key-$id.pem
echo "" > .download/mycs-key-00000.pem

# retrieve base image
regions=${1:-$(aws ec2 describe-regions --output text | cut -f4)}
base_amis=$(curl -sL https://cloud-images.ubuntu.com/locator/releasesTable \
  | python3 -c "import sys, re; data = sys.stdin.read(); data = re.sub(r',(\s*\])', r'\1', data); print(data)" \
  | jq -r '.aaData[] 
    | select(.[0] == "Amazon AWS" and .[2] == "'$UBUNTU_RELEASE'" and .[4] == "arm64" and (.[5] | contains("hvm")) and (.[5] | contains("ssd"))) 
    | "\(.[6])|\(.[1])|\(.[7] 
    | match("ami-[a-z0-9]+") 
    | .string)"')

# build images for each region
for r in $(echo "$regions"); do
  echo "Building AMI for region $r."
  aws::build_ami "$IMAGE_NAME" \
    "$r" "$base_amis" "$BUILD_DIR/packer/build-aws.pkr.hcl" 2>&1 \
    | tee $LOG_DIR/build-aws-$r.log &
done

# Wait for all parallel jobs to finish
wait