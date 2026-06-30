#!/bin/bash

export AWS_PAGER=

LOG_DIR=$(pwd)
BUILD_DIR=$(cd $(dirname $BASH_SOURCE)/.. && pwd)

which aws >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo -e "ERROR! The AWS CLI needs to be installed and configured. (https://aws.amazon.com/cli/)"
  exit 1
fi

which jq >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo -e "ERROR! The JQ CLI needs to be available in the system path. (https://stedolan.github.io/jq/download/)"
  exit 1
fi

if [[ -n $1 ]]; then
  IMAGE_NAME="mycs-bastion_$1"
else
  IMAGE_NAME="mycs-bastion"
fi

REGION="${2:-${AWS_DEFAULT_REGION-all}}"

set -euo pipefail

function aws::delete_images() {

  local region=$1
  local image_name=$2

  echo -e "\nDeleting images with name '$image_name' in region '$region'..."
  local images=$(aws \
    ec2 describe-images \
      --output json \
      --region "$region" \
      --owner self \
      --filters "Name=name,Values=$image_name")

  for i in $(echo "$images" | jq -r '.Images[].ImageId'); do

    local s=$(echo -e "$images" | jq -r  '.Images[] 
      | select(.ImageId=="'$i'") 
      | .BlockDeviceMappings[0].Ebs.SnapshotId')

    delete_msg="Deleting image '$image_name' with AMI '$i' and snapshot '$s' in region '$region'."
    echo -e "$delete_msg"

    aws ec2 deregister-image --region "$region" --image-id $i
    aws ec2 delete-snapshot --region "$region" --snapshot-id $s

    while [[ -n "$(aws \
      ec2 describe-images \
        --region "$region" \
        --owner self \
      | jq -r '.Images[] | select(.ImageId=="'$i'") | .ImageId')" ]]; do

        sleep 2
        echo -e "$delete_msg"
    done
    echo "Image '$image_name' has been deleted."
  done
}

if [[ -z $REGION || $REGION == all ]]; then
  regions=$(aws ec2 describe-regions --output text | cut -f4)
else
  regions=$REGION
fi
for r in $(echo "$regions"); do
  aws::delete_images "$r" "$IMAGE_NAME" &
done

# Wait for child processes to finish
wait