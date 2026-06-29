#!/bin/bash

LOG_DIR=$(pwd)
BUILD_DIR=$(cd $(dirname $BASH_SOURCE)/.. && pwd)

which gcloud >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  "ERROR! The Google SDK CLI needs to be installed and configured. (https://cloud.google.com/sdk/)"
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

if [[ -n $1 ]]; then
  IMAGE_NAME="appbricks-bastion-$1"
else
  IMAGE_NAME="appbricks-bastion"
fi

REGION="${2:-${GOOGLE_REGION-all}}"

set -euo pipefail

function google::delete_shared_image_objects() {
  
  local image_object_name=$1
  local publish_bucket=$2

  echo -e "Removing shared images and logs from bucket '$publish_bucket'..."

  set +e
  gsutil rm "gs://${publish_bucket}/appbricks-bastion/${image_object_name}.tar.gz"
  gsutil rm "gs://${publish_bucket}/logs/${image_object_name}.tar.gz.exporter.log"
  set -e

  echo -e "Done removing shared images and logs from bucket '$publish_bucket'."
}

function google::delete_shared_images() {

  local image=$1
  local region=$2

  local image_version=$(echo ${image#appbricks-bastion-*} | tr '[:lower:]' '[:upper:]' | tr '-' '.')
  local image_object_name="appbricks-bastion_${image_version}"

  local regions
  local publish_bucket

  if [[ -z $region || $region == all ]]; then
    regions=$(gcloud compute regions list --format json | jq -r '.[] | .name')
  else
    regions=$region
  fi
  for r in $(echo "$regions"); do
    publish_bucket=${GS_PUBLISH_BUCKET_PREFIX:-mycsimages}_${r}
    google::delete_shared_image_objects "$image_object_name" "$publish_bucket" &
  done
}

function google::delete_images() {

  local image=$1
  local region=$2

  local image_list=$(gcloud compute images list --filter="name~'$image'" | awk '/appbricks-bastion/{ print $1 }' 2>/dev/null)
  for image in $image_list; do
    echo -e "\nDeleting image with name '$image'..."
    gcloud compute images delete -q "$image" &

    google::delete_shared_images "$image" "$region"
  done
  if [[ -z $image_list ]]; then
    google::delete_shared_images "$image" "$region"
  fi
}

gcloud auth activate-service-account --key-file=$GOOGLE_CREDENTIALS
gcloud config set account $GOOGLE_ACCOUNT
gcloud config set project --quiet $GOOGLE_PROJECT

google::delete_images "$IMAGE_NAME" "$REGION"

# Wait for child processes to finish
wait