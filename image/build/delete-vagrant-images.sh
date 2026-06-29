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

existing_vers=$(curl -s "https://app.vagrantup.com/api/v1/box/appbricks/appbricks-bastion" \
  --request GET \
  --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
  | jq -r --arg v "$BOX_VERSION" '.versions[] | select(.version|test($v)) | .version')

for box_version in $existing_vers; do
  echo "Deleting vagrant box '$BOX_NAME' version '$box_version'" 
  curl -f -s "https://app.vagrantup.com/api/v1/box/appbricks/appbricks-bastion/version/${box_version}" \
    --request DELETE \
    --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
    >/dev/null 2>&1
done
