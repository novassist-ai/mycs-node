#!/bin/bash

# Shared helpers for OVHcloud Public Cloud (OpenStack) image build scripts.

function ovh::source_openrc() {
  if [[ -n "${OS_OPENRC_FILE:-}" && -f "${OS_OPENRC_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${OS_OPENRC_FILE}"
  fi
}

function ovh::validate_auth() {
  ovh::source_openrc

  if [[ -z "${OS_AUTH_URL:-}" ]]; then
    echo "ERROR! OS_AUTH_URL is not set. Source your OVH openrc.sh file or set OS_OPENRC_FILE."
    exit 1
  fi

  if [[ -z "${OS_REGION_NAME:-}" ]]; then
    echo "ERROR! OS_REGION_NAME is not set. Select the target OVH region in openrc.sh."
    exit 1
  fi

  if [[ -z "${OS_USERNAME:-}${OS_USERID:-}" ]]; then
    echo "ERROR! OS_USERNAME or OS_USERID is not set."
    exit 1
  fi

  if [[ -z "${OS_PASSWORD:-}${OS_APPLICATION_CREDENTIAL_SECRET:-}" ]]; then
    echo "ERROR! OS_PASSWORD or application credential secret is not set."
    exit 1
  fi

  if [[ -z "${OS_PROJECT_ID:-}${OS_PROJECT_NAME:-}${OS_TENANT_ID:-}${OS_TENANT_NAME:-}" ]]; then
    echo "ERROR! OS_PROJECT_ID or OS_PROJECT_NAME is not set."
    exit 1
  fi

  export OS_IDENTITY_API_VERSION="${OS_IDENTITY_API_VERSION:-3}"
  export OS_INTERFACE="${OS_INTERFACE:-public}"
}

function ovh::image_name_for_version() {
  local version=$1
  echo "mycs-bastion_${version}"
}

function ovh::resolve_openstack_ids() {
  local source_image_name=${1:-${OVH_SOURCE_IMAGE_NAME:-Ubuntu 24.04}}
  local flavor_name=${2:-${OVH_BUILD_FLAVOR:-d2-2}}
  local network_name=${3:-${OVH_PUBLIC_NETWORK_NAME:-Ext-Net}}

  export OVH_SOURCE_IMAGE_ID
  OVH_SOURCE_IMAGE_ID=$(openstack image list -f json \
    | jq -r --arg name "$source_image_name" \
      '.[] | select(.Name == $name) | .ID' \
    | head -1)

  if [[ -z "$OVH_SOURCE_IMAGE_ID" ]]; then
    echo "ERROR! Unable to find source image named '${source_image_name}' in region '${OS_REGION_NAME}'."
    exit 1
  fi

  export OVH_FLAVOR_ID
  OVH_FLAVOR_ID=$(openstack flavor list -f json \
    | jq -r --arg name "$flavor_name" \
      '.[] | select(.Name == $name) | .ID' \
    | head -1)

  if [[ -z "$OVH_FLAVOR_ID" ]]; then
    echo "ERROR! Unable to find flavor named '${flavor_name}' in region '${OS_REGION_NAME}'."
    exit 1
  fi

  export OVH_NETWORK_ID
  OVH_NETWORK_ID=$(openstack network list -f json \
    | jq -r --arg name "$network_name" \
      '.[] | select(.Name == $name) | .ID' \
    | head -1)

  if [[ -z "$OVH_NETWORK_ID" ]]; then
    echo "ERROR! Unable to find network named '${network_name}' in region '${OS_REGION_NAME}'."
    exit 1
  fi

  export OVH_TENANT_ID="${OS_PROJECT_ID:-${OS_TENANT_ID:-}}"
}

function ovh::image_property_args() {
  local version=$1
  cat <<EOF
--property distribution=ubuntu
--property hw_disk_bus=scsi
--property hw_scsi_model=virtio-scsi
--property hw_qemu_guest_agent=yes
--property image_original_user=ubuntu
--property os_type=linux
--property os_distro=ubuntu
--property mycs_bastion_version=${version}
EOF
}

function ovh::list_regions() {
  if [[ -n "${OVH_REGIONS:-}" ]]; then
    echo "$OVH_REGIONS"
    return
  fi

  set +e
  local regions
  regions=$(openstack region list -f value -c Region 2>/dev/null | sort -u)
  set -e

  if [[ -n "$regions" ]]; then
    echo "$regions"
    return
  fi

  # Fallback when region discovery is unavailable.
  echo "GRA9 SBG5 DE1 UK1 WAW1 BHS5"
}

function ovh::with_region() {
  local region=$1
  shift

  (
    export OS_REGION_NAME="$region"
    "$@"
  )
}
