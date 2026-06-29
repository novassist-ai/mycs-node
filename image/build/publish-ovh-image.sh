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

which jq >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR! The JQ CLI needs to be available in the system path. (https://stedolan.github.io/jq/download/)"
  exit 1
fi

ovh::validate_auth

if [[ -z "${1:-}" || -z "${2:-}" ]]; then
  echo "USAGE: publish-ovh-image.sh <source_region> <version> [dest_regions...]"
  echo
  echo "  source_region   Region where the image was built (e.g. GRA9)"
  echo "  version         Image version tag (e.g. 1.2.3 or D.251123055007)"
  echo "  dest_regions    Space-separated destination regions, or 'all'"
  exit 1
fi

SOURCE_REGION=$1
IMAGE_VERSION=$2
IMAGE_NAME=$(ovh::image_name_for_version "$IMAGE_VERSION")
shift 2
DEST_REGIONS=${*:-all}

set -euo pipefail

function ovh::delete_image_in_region() {
  local region=$1
  local image_name=$2

  ovh::with_region "$region" bash -c "
    set -euo pipefail
    ids=\$(openstack image list --name '${image_name}' -f value -c ID)
    for id in \$ids; do
      echo \"Deleting existing image '${image_name}' (\$id) in region '${region}'...\"
      openstack image delete \"\$id\"
    done
  "
}

function ovh::wait_for_image() {
  local region=$1
  local image_id=$2

  ovh::with_region "$region" bash -c "
    set -euo pipefail
    while true; do
      status=\$(openstack image show '${image_id}' -f value -c status)
      echo \"Image '${image_id}' in region '${region}' is \${status}...\"
      [[ \"\$status\" == \"active\" ]] && break
      sleep 10
    done
  "
}

function ovh::publish_image() {
  local source_region=$1
  local dest_region=$2
  local image_name=$3
  local image_version=$4
  local image_file=$5

  if [[ "$source_region" == "$dest_region" ]]; then
    echo "Skipping publish to source region '${source_region}'."
    return
  fi

  echo "Publishing '${image_name}' from '${source_region}' to '${dest_region}'..."

  ovh::delete_image_in_region "$dest_region" "$image_name"

  ovh::with_region "$dest_region" openstack image create \
    --disk-format qcow2 \
    --container-format bare \
    --private \
    --file "$image_file" \
    "$image_name" \
    --property distribution=ubuntu \
    --property hw_disk_bus=scsi \
    --property hw_scsi_model=virtio-scsi \
    --property hw_qemu_guest_agent=yes \
    --property image_original_user=ubuntu \
    --property os_type=linux \
    --property os_distro=ubuntu \
    --property "appbricks_version=${image_version}"

  local dest_image_id
  dest_image_id=$(ovh::with_region "$dest_region" openstack image list \
    --name "$image_name" -f value -c ID | head -1)
  ovh::wait_for_image "$dest_region" "$dest_image_id"

  echo "Published '${image_name}' to region '${dest_region}' (image id: ${dest_image_id})."
}

SOURCE_IMAGE_ID=$(ovh::with_region "$SOURCE_REGION" \
  openstack image list --name "$IMAGE_NAME" -f value -c ID | head -1)

if [[ -z "$SOURCE_IMAGE_ID" ]]; then
  echo "ERROR! Unable to find image '${IMAGE_NAME}' in region '${SOURCE_REGION}'."
  exit 1
fi

ovh::wait_for_image "$SOURCE_REGION" "$SOURCE_IMAGE_ID"

IMAGE_FILE="$BUILD_DIR/.build/ovh/${IMAGE_NAME}.qcow2"
mkdir -p "$(dirname "$IMAGE_FILE")"
rm -f "$IMAGE_FILE"

echo "Exporting image '${IMAGE_NAME}' (${SOURCE_IMAGE_ID}) from region '${SOURCE_REGION}'..."
ovh::with_region "$SOURCE_REGION" \
  openstack image save --file "$IMAGE_FILE" "$SOURCE_IMAGE_ID"

if [[ ! -s "$IMAGE_FILE" ]]; then
  echo "ERROR! Failed to export image '${IMAGE_NAME}' to '${IMAGE_FILE}'."
  exit 1
fi

if [[ "$DEST_REGIONS" == all ]]; then
  regions=$(ovh::list_regions)
else
  regions=$DEST_REGIONS
fi

for r in $regions; do
  ovh::publish_image \
    "$SOURCE_REGION" \
    "$r" \
    "$IMAGE_NAME" \
    "$IMAGE_VERSION" \
    "$IMAGE_FILE" &
done

wait

echo "Publish complete for image '${IMAGE_NAME}'."
