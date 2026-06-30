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

if [[ -z $2 ]]; then
  echo -e "ERROR! Only tagged image builds can be published"
  exit 1
fi
IMAGE_NAME="mycs-bastion_$2"

set -euo pipefail

function aws::delete_image() {

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
    echo "done"
  done
}

function aws::publish_ami() {

  local dest_region=$1
  local source_region=$2
  local source_ami=$3
  local image_name=$4

  aws::delete_image "$dest_region" "$image_name"
  echo "Publishing image '${image_name}' to region '${dest_region}'..."

  image_id=$(aws \
    ec2 copy-image \
      --source-image-id "$source_ami" \
      --source-region "$source_region" \
      --region "$dest_region" \
      --name "$image_name" \
    | jq -r '.ImageId')

  state="pending"
  while [[ "$state" != "available" ]]; do

    echo "Waiting for image '$image_name' in region '$dest_region' to become available."
    sleep 2

    state=$(aws \
      ec2 describe-images \
        --output json \
        --region "$dest_region" \
        --image-ids "$image_id" \
      | jq -r '.Images[].State')
  done

  echo "Making image '$image_name' in region '$dest_region' public."
  aws ec2 modify-image-attribute \
    --region "$dest_region" \
    --image-id "$image_id" \
    --launch-permission "Add=[{Group=all}]"
}

SOURCE_REGION=$1
SOURCE_AMI=$(aws \
  ec2 describe-images \
    --output json \
    --region "$SOURCE_REGION" \
    --owner self \
    --filters "Name=name,Values=$IMAGE_NAME" \
  | jq -r '.Images[].ImageId')

if [[ -z $SOURCE_AMI ]]; then
  "ERROR! Unable to find AMI for image named '$IMAGE_NAME' in region '$SOURCE_REGION'"
  exit 1
fi

aws ec2 modify-image-attribute \
  --region "$SOURCE_REGION" \
  --image-id "$SOURCE_AMI" \
  --launch-permission "Add=[{Group=all}]"

regions=${3:-$(aws ec2 describe-regions --output text | cut -f4)}
for r in $(echo "$regions"); do
  if [[ "$r" != "$SOURCE_REGION" ]]; then
    aws::publish_ami "$r" "$SOURCE_REGION" "$SOURCE_AMI" "$IMAGE_NAME" &
  fi
done

# Wait for all parallel jobs to finish
wait