#!/usr/bin/env bash
# Bump novassist-ai/homebrew-tap Formula/vpn-node-builder.rb to a vpnb_* release tag.
#
# Usage:
#   bump-homebrew-vpn-node-builder.sh -t vpnb_0.0.1 [-d /path/to/homebrew-tap]
#
# Expects the tap checkout at -d (default: ./homebrew-tap). Updates url + sha256
# (and the VPNB_IMAGE pin example in caveats). Does not commit.

set -euo pipefail

release_tag=
tap_dir=homebrew-tap
repo=novassist-ai/mycs-node

usage() {
  echo "USAGE: $0 -t vpnb_X.Y.Z [-d TAP_DIR] [-r GITHUB_REPO]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tag)
      release_tag=$2
      shift
      ;;
    -d|--tap-dir)
      tap_dir=$2
      shift
      ;;
    -r|--repo)
      repo=$2
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR! Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z "${release_tag}" ]]; then
  echo "ERROR! Release tag is required (-t vpnb_X.Y.Z)." >&2
  usage
  exit 1
fi

if [[ ! "${release_tag}" =~ ^vpnb_[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR! Tag must look like vpnb_X.Y.Z (got ${release_tag})." >&2
  exit 1
fi

version=${release_tag#vpnb_}
formula="${tap_dir}/Formula/vpn-node-builder.rb"
if [[ ! -f "${formula}" ]]; then
  echo "ERROR! Formula not found: ${formula}" >&2
  exit 1
fi

url="https://github.com/${repo}/archive/refs/tags/${release_tag}.tar.gz"
tmpdir=$(mktemp -d)
trap 'rm -rf "${tmpdir}"' EXIT
tarball="${tmpdir}/${release_tag}.tar.gz"

echo "Downloading ${url}..."
# Tag archive can lag a few seconds after git push.
attempts=12
for ((i = 1; i <= attempts; i++)); do
  if curl -fsSL -o "${tarball}" "${url}"; then
    break
  fi
  if [[ $i -eq $attempts ]]; then
    echo "ERROR! Failed to download ${url} after ${attempts} attempts." >&2
    exit 1
  fi
  echo "Archive not ready yet (attempt ${i}/${attempts}); retrying in 5s..."
  sleep 5
done

sha256=$(shasum -a 256 "${tarball}" | awk '{ print $1 }')
echo "sha256: ${sha256}"

# Portable in-place sed (GNU/BSD).
sed_i() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

sed_i -E \
  "s|url \"https://github.com/.*/archive/refs/tags/vpnb_[0-9]+\\.[0-9]+\\.[0-9]+\\.tar\\.gz\"|url \"${url}\"|" \
  "${formula}"
sed_i -E \
  "s|sha256 \"[0-9a-f]{64}\"|sha256 \"${sha256}\"|" \
  "${formula}"
sed_i -E \
  "s|vpn-node-builder:[0-9]+\\.[0-9]+\\.[0-9]+|vpn-node-builder:${version}|g" \
  "${formula}"

echo "Updated ${formula} → ${release_tag}"
grep -E '^\s*(url|sha256) ' "${formula}" || true
