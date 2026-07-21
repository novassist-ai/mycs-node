#!/bin/bash
#
# List or delete MyCS node qcow2 objects under novassist-public.
#
# USAGE:
#   ./build/delete-qcow2-images.sh [--all] <CHANNEL> [ARCH]
#
# CHANNEL:  dev | prod
# ARCH:     amd64 | arm64 | all   (default: all)
#
# Without --all, lists matching objects and exits 0 (dry-run).
# With --all, deletes versioned images for the selected arch(es) under the
# channel prefix.
#
# Object layout (flat under channel):
#   mycs-releases/mycs-node/image/<CHANNEL>/mycs-node-image_<VERSION>_<ARCH>.qcow2
#
# Env:
#   QCOW2_S3_BUCKET   (default: novassist-public)
#   AWS_DEFAULT_REGION (default: us-east-1)
#

export AWS_PAGER=

which aws >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR! The AWS CLI needs to be installed and configured."
  exit 1
fi

DELETE_ALL=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --all|-a)
      DELETE_ALL=1
      ;;
    -h|--help)
      echo "USAGE: $(basename "$0") [--all] <CHANNEL> [ARCH]"
      echo "  --all     Delete objects (otherwise list only)"
      echo "  CHANNEL   dev | prod"
      echo "  ARCH      amd64 | arm64 | all (default: all)"
      exit 0
      ;;
    *)
      ARGS+=("$arg")
      ;;
  esac
done

if [[ ${#ARGS[@]} -lt 1 ]]; then
  echo "USAGE: $(basename "$0") [--all] <CHANNEL> [ARCH]"
  exit 1
fi

CHANNEL=${ARGS[0]}
TARGET_ARCH=${ARGS[1]:-all}

case "$CHANNEL" in
  dev|prod) ;;
  *)
    echo "ERROR! CHANNEL must be dev or prod (got '${CHANNEL}')."
    exit 1
    ;;
esac

case "$TARGET_ARCH" in
  amd64|arm64|all) ;;
  *)
    echo "ERROR! ARCH must be amd64, arm64, or all (got '${TARGET_ARCH}')."
    exit 1
    ;;
esac

BUCKET=${QCOW2_S3_BUCKET:-novassist-public}
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
export AWS_DEFAULT_REGION

PREFIX="mycs-releases/mycs-node/image/${CHANNEL}/"

set -euo pipefail

function qcow2::list_keys() {
  aws s3api list-objects-v2 \
    --bucket "$BUCKET" \
    --prefix "$PREFIX" \
    --query 'Contents[].Key' \
    --output text \
    | tr '\t' '\n' \
    | grep -E 'mycs-node-image.*\.qcow2$' \
    || true
}

function qcow2::keys_for_arch() {
  local arch=$1
  local key
  while IFS= read -r key; do
    [[ -z "$key" || "$key" == "None" ]] && continue
    case "$key" in
      */mycs-node-image_latest_"${arch}".qcow2|*/mycs-node-image_*_"${arch}".qcow2)
        echo "$key"
        ;;
    esac
  done <<< "$(qcow2::list_keys)"
}

function qcow2::process_arch() {
  local arch=$1
  local keys
  keys=$(qcow2::keys_for_arch "$arch")

  if [[ -z "$keys" ]]; then
    echo "No qcow2 objects for arch '${arch}' under s3://${BUCKET}/${PREFIX}"
    return 0
  fi

  echo "Objects for arch '${arch}' under s3://${BUCKET}/${PREFIX}:"
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    echo "  - ${key}"
  done <<< "$keys"

  if [[ $DELETE_ALL -ne 1 ]]; then
    echo "(dry-run; pass --all to delete)"
    return 0
  fi

  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    echo "Deleting s3://${BUCKET}/${key}"
    aws s3 rm "s3://${BUCKET}/${key}"
  done <<< "$keys"
}

if [[ $TARGET_ARCH == all ]]; then
  qcow2::process_arch amd64
  qcow2::process_arch arm64
else
  qcow2::process_arch "$TARGET_ARCH"
fi

if [[ $DELETE_ALL -eq 1 ]]; then
  echo "Delete complete for channel '${CHANNEL}' arch '${TARGET_ARCH}'."
else
  echo "Dry-run complete. Re-run with --all to delete."
fi
