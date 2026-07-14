#!/bin/bash

LOG_DIR=$(pwd)
BUILD_DIR=$(cd $(dirname $BASH_SOURCE)/.. && pwd)

which gcloud >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    "ERROR! The Google SDK CLI needs to be installed and configured. (https://cloud.google.com/sdk/)"
    exit 1
fi

if [[ ! -e $GOOGLE_CREDENTIALS ]]; then
    "ERROR! Invalid Google service account key file path in the GOOGLE_CREDENTIALS environment variable"
    exit 1
fi
if [[ -z $GOOGLE_REGION ]]; then
    "ERROR! The source image object's region must be provided in the GOOGLE_REGION environment variable"
    exit 1
fi

if [[ -z $1 ]]; then
  echo -e "ERROR! Only tagged image builds can be published"
  exit 1
fi

SOURCE_BUCKET=${GS_PUBLISH_BUCKET_PREFIX:-mycsimages}_${GOOGLE_REGION}
IMAGE_OBJECT_NAME="mycs-node-image_$1"
REGION="${2:-all}"

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

function google::publish_image_object() {

  local region=$1

  local publish_bucket=${GS_PUBLISH_BUCKET_PREFIX:-mycsimages}_${region}
  google::create_bucket "$publish_bucket" "$region"

  gsutil cp \
    "gs://${SOURCE_BUCKET}/mycs-node-image/${IMAGE_OBJECT_NAME}.tar.gz" \
    "gs://${publish_bucket}/mycs-node-image/${IMAGE_OBJECT_NAME}.tar.gz"
}

gcloud auth activate-service-account --key-file=$GOOGLE_CREDENTIALS
gcloud config set account $GOOGLE_ACCOUNT
gcloud config set project --quiet $GOOGLE_PROJECT

if [[ -z $REGION || $REGION == all ]]; then
  regions=$(gcloud compute regions list --format json | jq -r '.[] | .name')
else
  regions=$REGION
fi  
for r in $(echo "$regions"); do
  if [[ "$r" != "$GOOGLE_REGION" ]]; then
    google::publish_image_object "$r" &
  fi
done

# Wait for all parallel jobs to finish
wait
