#!/bin/bash

LOG_DIR=$(pwd)
BUILD_DIR=$(cd $(dirname $BASH_SOURCE)/.. && pwd)

which az >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  "ERROR! The Azure SDK CLI needs to be installed and configured. (https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)"
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

ARM_DEFAULT_RESOURCE_GROUP=${ARM_DEFAULT_RESOURCE_GROUP:-external}
ARM_PUBLISH_STORAGE_ACCOUNT_PREFIX=${ARM_PUBLISH_STORAGE_ACCOUNT_PREFIX:-mycs}
ARM_PUBLISH_CONTAINER=${ARM_PUBLISH_CONTAINER:-nodeimage}

# Append version to image name
IMAGE_SNAPSHOT_PREFIX="mycsbastion"
if [[ -z $1 ]]; then
  echo -e "ERROR! Snapshot search pattern needs to be provided as the first argument"
  exit 1
fi
PUBLISH_SNAPSHOT_PATTERN="${IMAGE_SNAPSHOT_PREFIX}_($1)_.*" 

if [[ -z $2 ]]; then
  SNAPSHOT_LOCATION=$(az group show --name $ARM_DEFAULT_RESOURCE_GROUP | jq -r .location)
fi

if [[ $3 == all ]]; then
  STORAGE_LOCATIONS=${location:-$(az account list-locations | jq -r '.[].name' | sort)}  
else
  STORAGE_LOCATIONS=${3:-$SNAPSHOT_LOCATION}
fi

SKIP_REGIONS='
  asia:
  asiapacific:
  australia:
  australiacentral2:
  brazil:
  brazilsoutheast:
  canada:
  centraluseuap:
  centralusstage:
  eastasiastage:
  eastus2euap:
  eastus2stage:
  eastusstage:
  eastusstg:
  europe:
  france:
  francesouth:
  germany:
  germanynorth:
  global:
  india:
  japan:
  jioindiacentral:
  korea:
  northcentralusstage:
  norway:
  norwaywest:
  singapore:
  southafrica:
  southafricawest:
  southcentralusstage:
  southcentralusstg:
  southeastasiastage:
  switzerland:
  switzerlandwest:
  uae:
  uaecentral:
  uk:
  unitedstates:
  unitedstateseuap:
  westus2stage:
  westusstage:'

set -euo pipefail

function azure::delete_image_snapshot() {

  local location=$1
  local publish_vhd_name=$2
  local snapshot_name=$3

  local storage_account=${ARM_PUBLISH_STORAGE_ACCOUNT_PREFIX}${location}
  local container_name=${ARM_PUBLISH_CONTAINER}

  account_key=$(az storage account keys list \
    --account-name "$storage_account" \
    --resource-group "$ARM_DEFAULT_RESOURCE_GROUP" 2>/dev/null \
    | jq -r '.[0] | .value')
  if [[ -z $account_key ]]; then
    echo "....skipping storage account '$storage_account'."
    return
  fi

  echo "Searching for image blob for snapshot '$snapshot_name' in container '/${storage_account}/${container_name}/' at location '$location'."

  blob_list=$(az storage blob list \
    --container-name "$container_name" \
    --account-key "$account_key" \
    --account-name "$storage_account" \
    | jq -r '.[].name')

  echo -e "$blob_list" | grep "${publish_vhd_name}" 2>&1 >/dev/null
  if [[ $? -eq 0 ]]; then
    echo "Deleting image for snapshot '$snapshot_name' found at '/${storage_account}/${container_name}/${publish_vhd_name}'..."
    az storage blob delete \
      --name "$publish_vhd_name" \
      --container-name "$container_name" \
      --account-key "$account_key" \
      --account-name "$storage_account"
  fi
}

set +e
echo -e "\nRetrieving snapshots to delete that match pattern '$PUBLISH_SNAPSHOT_PATTERN'..."
snapshot_list=$(az snapshot list --resource-group "$ARM_DEFAULT_RESOURCE_GROUP" \
  | jq -r \
    --arg pattern $PUBLISH_SNAPSHOT_PATTERN \
    '.[] | select(.name|test($pattern)) | "\(.id)|\(.name)"')

for s in $(echo -e "$snapshot_list"); do

  id=$(echo $s | awk -F'|' '{print $1}')
  snapshot_name=$(echo $s | awk -F'|' '{print $2}')
  version=${snapshot_name%_*} && version=${version#*_} && version=$(echo "$version" | tr '_' '.')
  publish_vhd_name="mycs-node-image_${version}.vhd"

  echo -e "\nDeleting image snapshot '$snapshot_name'."
  az snapshot delete --ids $id

  for l in $(echo "$STORAGE_LOCATIONS"); do
    (echo "$SKIP_REGIONS" | grep "  $l:" 2>&1 >/dev/null) || \
      azure::delete_image_snapshot "$l" "$publish_vhd_name" "$snapshot_name" &
  done
  wait

done
