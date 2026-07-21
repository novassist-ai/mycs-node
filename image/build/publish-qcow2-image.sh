#!/bin/bash
#
# Upload a built MyCS node qcow2 image to s3://novassist-public and point a
# zero-byte "latest" object at it via website redirect metadata.
#
# USAGE:
#   ./build/publish-qcow2-image.sh <VERSION> <ARCH> <CHANNEL>
#
# CHANNEL:  dev | prod
# ARCH:     amd64 | arm64
#
# Object layout:
#   s3://novassist-public/mycs-releases/mycs-node/image/<CHANNEL>/mycs-node-image_<VERSION>_<ARCH>.qcow2
#   s3://novassist-public/mycs-releases/mycs-node/image/<CHANNEL>/mycs-node-image_latest_<ARCH>.qcow2
#     (0-byte; x-amz-website-redirect-location → the versioned object)
#
# Public downloadability: Object Ownership is BucketOwnerEnforced (no ACLs).
# This script ensures a bucket-policy statement allowing public s3:GetObject on
#   arn:aws:s3:::<bucket>/mycs-releases/mycs-node/image/*
# if that statement is not already present. Block Public Access must allow
# public bucket policies for this to take effect.
#
# Before upload, any existing object at the versioned key is deleted so a
# re-run of the same VERSION/ARCH (e.g. after a sibling job failed) replaces
# the prior artifact cleanly.
#
# Env:
#   QCOW2_S3_BUCKET   (default: novassist-public)
#   AWS_DEFAULT_REGION (default: us-east-1)
#   AWS credentials via the environment / instance profile
#     (needs s3:GetBucketPolicy, s3:PutBucketPolicy, and object R/W)
#

export AWS_PAGER=

BUILD_DIR=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)

which aws >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR! The AWS CLI needs to be installed and configured."
  exit 1
fi

which jq >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR! jq is required to manage the S3 bucket policy."
  exit 1
fi

if [[ $# -lt 3 ]]; then
  echo "USAGE: $(basename "$0") <VERSION> <ARCH> <CHANNEL>"
  echo "  VERSION   Image version (e.g. 0.1.0 or 0.2.0-dev1)"
  echo "  ARCH      amd64 | arm64"
  echo "  CHANNEL   dev | prod"
  exit 1
fi

IMAGE_VERSION=$1
TARGET_ARCH=$2
CHANNEL=$3

case "$TARGET_ARCH" in
  amd64|arm64) ;;
  *)
    echo "ERROR! ARCH must be amd64 or arm64 (got '${TARGET_ARCH}')."
    exit 1
    ;;
esac

case "$CHANNEL" in
  dev|prod) ;;
  *)
    echo "ERROR! CHANNEL must be dev or prod (got '${CHANNEL}')."
    exit 1
    ;;
esac

BUCKET=${QCOW2_S3_BUCKET:-novassist-public}
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
export AWS_DEFAULT_REGION

IMAGE_NAME="mycs-node-image_${IMAGE_VERSION}"
LOCAL_IMAGE="$BUILD_DIR/.build/qcow2/${IMAGE_NAME}.qcow2"
IMAGE_PREFIX="mycs-releases/mycs-node/image"
PREFIX="${IMAGE_PREFIX}/${CHANNEL}"
VERSIONED_KEY="${PREFIX}/${IMAGE_NAME}_${TARGET_ARCH}.qcow2"
LATEST_KEY="${PREFIX}/mycs-node-image_latest_${TARGET_ARCH}.qcow2"
# Website redirect targets another key in the same bucket (leading slash).
REDIRECT_LOCATION="/${VERSIONED_KEY}"
PUBLIC_BASE="https://${BUCKET}.s3.${AWS_DEFAULT_REGION}.amazonaws.com"
PUBLIC_RESOURCE_ARN="arn:aws:s3:::${BUCKET}/${IMAGE_PREFIX}/*"
PUBLIC_POLICY_SID="PublicReadMyCSNodeImages"

set -euo pipefail

# Ensure bucket policy allows anonymous GetObject on mycs-node image objects.
function qcow2::ensure_public_read_policy() {
  local existing_json policy_doc updated
  local tmp_err
  tmp_err=$(mktemp)

  if ! existing_json=$(aws s3api get-bucket-policy --bucket "$BUCKET" --output json 2>"$tmp_err"); then
    if grep -q NoSuchBucketPolicy "$tmp_err"; then
      policy_doc='{"Version":"2012-10-17","Statement":[]}'
    else
      echo "ERROR! Failed to read bucket policy for s3://${BUCKET}:"
      cat "$tmp_err"
      rm -f "$tmp_err"
      exit 1
    fi
  else
    policy_doc=$(echo "$existing_json" | jq -c '.Policy | fromjson')
  fi
  rm -f "$tmp_err"

  if echo "$policy_doc" | jq -e --arg sid "$PUBLIC_POLICY_SID" --arg res "$PUBLIC_RESOURCE_ARN" '
      .Statement
      | map(select(
          (.Sid == $sid)
          or (
            (.Effect == "Allow")
            and (
              (.Principal == "*")
              or (.Principal.AWS == "*")
              or ((.Principal.AWS | type) == "array" and (.Principal.AWS | index("*") != null))
            )
            and (
              (.Action == "s3:GetObject")
              or ((.Action | type) == "array" and (.Action | index("s3:GetObject") != null))
            )
            and (
              (.Resource == $res)
              or ((.Resource | type) == "array" and (.Resource | index($res) != null))
            )
          )
        ))
      | length > 0
    ' >/dev/null; then
    echo "Bucket policy already allows public GetObject on ${PUBLIC_RESOURCE_ARN}"
    return 0
  fi

  echo "Adding public GetObject bucket policy statement for ${PUBLIC_RESOURCE_ARN}"
  updated=$(echo "$policy_doc" | jq -c --arg sid "$PUBLIC_POLICY_SID" --arg res "$PUBLIC_RESOURCE_ARN" '
    .Statement += [{
      "Sid": $sid,
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": $res
    }]
  ')

  if ! aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$updated"; then
    echo "ERROR! Failed to put bucket policy on s3://${BUCKET}."
    echo "  Ensure the IAM principal can call s3:PutBucketPolicy, and that"
    echo "  Block Public Access allows public bucket policies on this bucket."
    exit 1
  fi
  echo "Bucket policy updated."
}

if [[ ! -f "$LOCAL_IMAGE" ]]; then
  echo "ERROR! Local qcow2 not found: ${LOCAL_IMAGE}"
  echo "Run build/build-qcow2-image.sh ${IMAGE_VERSION} ${TARGET_ARCH} first."
  exit 1
fi

echo "Publishing ${LOCAL_IMAGE}"
echo "  bucket:    s3://${BUCKET}"
echo "  versioned: s3://${BUCKET}/${VERSIONED_KEY}"
echo "  latest:    s3://${BUCKET}/${LATEST_KEY} → ${REDIRECT_LOCATION}"

qcow2::ensure_public_read_policy

# Drop a prior upload of this VERSION/ARCH so retries do not leave stale bytes.
if aws s3api head-object --bucket "$BUCKET" --key "$VERSIONED_KEY" >/dev/null 2>&1; then
  echo "Removing existing versioned object s3://${BUCKET}/${VERSIONED_KEY}"
  aws s3 rm "s3://${BUCKET}/${VERSIONED_KEY}"
fi

# Clean legacy layout (arch as path segment) for the same VERSION if present.
LEGACY_VERSIONED_KEY="${PREFIX}/${TARGET_ARCH}/${IMAGE_NAME}.qcow2"
LEGACY_LATEST_KEY="${PREFIX}/${TARGET_ARCH}/mycs-node-image.qcow2"
for legacy in "$LEGACY_VERSIONED_KEY" "$LEGACY_LATEST_KEY"; do
  if aws s3api head-object --bucket "$BUCKET" --key "$legacy" >/dev/null 2>&1; then
    echo "Removing legacy object s3://${BUCKET}/${legacy}"
    aws s3 rm "s3://${BUCKET}/${legacy}"
  fi
done

aws s3 cp "$LOCAL_IMAGE" "s3://${BUCKET}/${VERSIONED_KEY}" \
  --content-type application/octet-stream

TMP_EMPTY=$(mktemp)
: > "$TMP_EMPTY"
aws s3api put-object \
  --bucket "$BUCKET" \
  --key "$LATEST_KEY" \
  --body "$TMP_EMPTY" \
  --content-type application/octet-stream \
  --website-redirect-location "$REDIRECT_LOCATION" \
  >/dev/null
rm -f "$TMP_EMPTY"

echo "Published qcow2 ${IMAGE_NAME} (${TARGET_ARCH}/${CHANNEL})."
echo "  versioned: ${PUBLIC_BASE}/${VERSIONED_KEY}"
echo "  latest:    ${PUBLIC_BASE}/${LATEST_KEY}"
