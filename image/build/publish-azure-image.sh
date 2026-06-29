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

if [[ -z $1 ]]; then
  echo -e "ERROR! You need to provide the snapshot location as first argument"
  exit 1
fi

# Append version to image name
IMAGE_SNAPSHOT_PREFIX="appbricksbastion"
if [[ -z $2 ]]; then
  echo -e "ERROR! Only tagged image builds can be published"
  exit 1
fi
PUBLISH_VHD_NAME="appbricks-bastion_${2}.vhd"
PUBLISH_SNAPSHOT_NAME="${IMAGE_SNAPSHOT_PREFIX}_$(echo $2 | sed 's/\./_/g')_${1}" 

echo "Publishing image snapshot '$PUBLISH_SNAPSHOT_NAME' to unmanaged VHD image '$PUBLISH_VHD_NAME'."

if [[ $3 == all ]]; then
  locations=${location:-$(az account list-locations | jq -r '.[].name' | sort)}  
elif [[ -z $3 ]]; then
  locations=$1
else
  locations=${3:-$(az group show --name $ARM_DEFAULT_RESOURCE_GROUP | jq -r .location)}
fi

set -euo pipefail

function azure::publish_image_snapshot() {

  local location=$1
  local sas_url=$2

  local storage_account=${ARM_PUBLISH_STORAGE_ACCOUNT_PREFIX}${location}
  local container_name=${ARM_PUBLISH_CONTAINER}

  set +e
  local salookup=$(az storage account list \
    | jq -r --arg sa "${storage_account}" '.[] | select(.name == $sa) | .name')
  if [[ -z $salookup ]]; then
    set -e
    echo -e "Creating Azure Storage account '${storage_account}'."
    az storage account create \
      --name "$storage_account" \
      --location "$location" \
      --resource-group "$ARM_DEFAULT_RESOURCE_GROUP" \
      --sku Standard_LRS \
      --output none
  else
    set -e
  fi

  local account_key=$(az storage account keys list \
    --account-name "$storage_account" \
    --resource-group "$ARM_DEFAULT_RESOURCE_GROUP" \
    | jq -r '.[0] | .value')

  set +e
  az storage container list --account-key "${account_key}" --account-name "${storage_account}" \
    | jq -r '.[].name' | grep "${container_name}" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    set -e
    echo -e "Creating Azure container '${container_name}' in storage account '${storage_account}'."
    az storage container create \
      --name "${container_name}" \
      --account-name "${storage_account}" \
      --public-access blob \
      --output none    
  else
    set -e
  fi

  local blob_list=$(az storage blob list \
    --container-name "$container_name" \
    --account-key "$account_key" \
    --account-name "$storage_account" \
    | jq -r '.[].name')

  set +e
  echo -e "$blob_list" | grep "${PUBLISH_VHD_NAME}" 2>&1 >/dev/null
  if [[ $? -eq 0 ]]; then
    echo "Unmanaged VHD exists at '/${storage_account}/${container_name}/${PUBLISH_VHD_NAME}' skipping upload to container '$container_name'."
    return
  fi
  set -e

  echo "Copying image snapshot '$PUBLISH_SNAPSHOT_NAME' to unmanaged VHD image at '/${storage_account}/${container_name}/${PUBLISH_VHD_NAME}'..."
  az storage blob copy start \
    --destination-blob "$PUBLISH_VHD_NAME" \
    --destination-container "$container_name" \
    --account-key "$account_key" \
    --account-name "$storage_account" \
    --source-uri "$sas_url"

  while true; do

    local blob_info=$(az storage blob show \
      --name "$PUBLISH_VHD_NAME" \
      --container-name "$container_name" \
      --account-key "$account_key" \
      --account-name "$storage_account")
    
    local progress=$(echo "$blob_info" | jq -r .properties.copy.progress)
    echo "'$PUBLISH_SNAPSHOT_NAME' => '/${storage_account}/${container_name}/${PUBLISH_VHD_NAME}': $progress complete..."

    local status=$(echo "$blob_info" | jq -r .properties.copy.status)
    if [[ $status == "failed" ]]; then
      echo "ERROR! Failed to copy snapshot to storage containter '$container_name'."
    fi
    if [[ $status == "success" ]]; then
      echo "Done copying image snapshot '$PUBLISH_SNAPSHOT_NAME' to '/${storage_account}/${container_name}/${PUBLISH_VHD_NAME}'."
      break
    fi
    sleep 5
  done
}

# retrieve url of build image snapshot
sas_url=$(az snapshot grant-access \
  --resource-group "$ARM_DEFAULT_RESOURCE_GROUP" \
  --name "$PUBLISH_SNAPSHOT_NAME" \
  --duration-in-seconds 21600 \
  --access-level Read \
  | jq -r .accessSas)

skip_regions='
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

for l in $(echo "$locations"); do
  (echo "$skip_regions" | grep "  $l:" 2>&1 >/dev/null) || \
    azure::publish_image_snapshot "$l" "$sas_url" &
done

# Wait for all parallel jobs to finish
wait

set +e
az snapshot revoke-access \
  --resource-group "$ARM_DEFAULT_RESOURCE_GROUP" \
  --name "$PUBLISH_SNAPSHOT_NAME" 2>&1 >/dev/null
set -e
