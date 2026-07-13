#!/bin/bash

LOG_DIR=$(pwd)
BUILD_DIR=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)
# shellcheck source=../scripts/ovh/common.sh
source "$BUILD_DIR/scripts/ovh/common.sh"

which openstack >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR! The OpenStack CLI needs to be installed. (https://docs.openstack.org/python-openstackclient/)"
  exit 1
fi

ovh::validate_auth

if [[ -n "${1:-}" ]]; then
  IMAGE_NAME=$(ovh::image_name_for_version "$1")
else
  IMAGE_NAME="mycs-bastion"
fi

REGION="${2:-all}"

set -euo pipefail

function ovh::delete_images() {
  local region=$1
  local image_name=$2

  ovh::with_region "$region" bash -c "
    set -euo pipefail
    ids=\$(openstack image list --name '${image_name}' -f value -c ID)
    for id in \$ids; do
      echo \"Deleting image '${image_name}' (\$id) in region '${region}'...\"
      openstack image delete \"\$id\"
    done
    if [[ -z \"\$ids\" ]]; then
      echo \"No images named '${image_name}' in region '${region}'.\"
    fi
  "
}

if [[ -z "$REGION" || "$REGION" == all ]]; then
  regions=$(ovh::list_regions)
else
  regions=$REGION
fi

for r in $regions; do
  ovh::delete_images "$r" "$IMAGE_NAME" &
done

wait
