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
IMAGE_NAME="mycs-node-image_$2"

set -euo pipefail

# Returns 0 if the region is enabled for this account (or does not require opt-in).
function aws::region_enabled() {
  local region=$1
  local query_region=${2:-${AWS_DEFAULT_REGION:-us-east-1}}
  local status

  status=$(aws ec2 describe-regions \
    --all-regions \
    --region "$query_region" \
    --filters "Name=region-name,Values=$region" \
    --query 'Regions[0].OptInStatus' \
    --output text 2>/dev/null || true)

  [[ "$status" == "opt-in-not-required" || "$status" == "opted-in" ]]
}

# Ensure account-level AMI Block Public Access is off in the region so AMIs can be shared publicly.
function aws::ensure_ami_public_shareable() {
  local region=$1
  local state
  local managed_by

  local bpa
  bpa=$(aws ec2 get-image-block-public-access-state --region "$region" --output json)
  state=$(echo "$bpa" | jq -r '.ImageBlockPublicAccessState // empty')
  managed_by=$(echo "$bpa" | jq -r '.ManagedBy // "account"')

  if [[ "$state" == "unblocked" ]]; then
    return 0
  fi

  if [[ "$managed_by" == "declarative-policy" ]]; then
    echo "ERROR! AMI Block Public Access is enabled in '$region' by a declarative policy and cannot be disabled from this account."
    return 1
  fi

  echo "Disabling AMI Block Public Access in region '$region' (current state: $state)..."
  aws ec2 disable-image-block-public-access --region "$region" >/dev/null

  # Setting can take a short time to apply; wait until API reports unblocked.
  local attempts=0
  while [[ $attempts -lt 30 ]]; do
    state=$(aws ec2 get-image-block-public-access-state \
      --region "$region" \
      --query 'ImageBlockPublicAccessState' \
      --output text)
    if [[ "$state" == "unblocked" ]]; then
      echo "AMI Block Public Access is unblocked in region '$region'."
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 2
  done

  echo "ERROR! Timed out waiting for AMI Block Public Access to become unblocked in region '$region'."
  return 1
}

function aws::make_image_public() {
  local region=$1
  local image_id=$2
  local image_name=$3

  aws::ensure_ami_public_shareable "$region"

  echo "Making image '$image_name' in region '$region' public."
  aws ec2 modify-image-attribute \
    --region "$region" \
    --image-id "$image_id" \
    --launch-permission "Add=[{Group=all}]"
}

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

  aws::make_image_public "$dest_region" "$image_id" "$image_name"
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

aws::make_image_public "$SOURCE_REGION" "$SOURCE_AMI" "$IMAGE_NAME"

regions=${3:-$(aws ec2 describe-regions --output text | cut -f4)}
pids=()
status=0
for r in $(echo "$regions"); do
  if [[ "$r" == "$SOURCE_REGION" ]]; then
    continue
  fi
  if ! aws::region_enabled "$r" "$SOURCE_REGION"; then
    echo "WARNING: Skipping publish to region '$r' — not enabled for this AWS account."
    continue
  fi
  aws::publish_ami "$r" "$SOURCE_REGION" "$SOURCE_AMI" "$IMAGE_NAME" &
  pids+=($!)
done

for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    status=1
  fi
done
exit "$status"
