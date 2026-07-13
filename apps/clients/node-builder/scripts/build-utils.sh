#!/bin/bash

# Build shared Go utilities used by cloud/cookbook local recipes.
# Usage:
#   ./apps/clients/node-builder/scripts/build-utils.sh :dev:clean-all:
#   ./apps/clients/node-builder/scripts/build-utils.sh :release:clean-all: <os> <arch>

action=${1:-}
os=${2:-}
arch=${3:-}

set -xeuo pipefail

script_dir=$(cd "$(dirname "$BASH_SOURCE")" && pwd)
root_dir=$(cd "${script_dir}/../../../.." && pwd)
golang_dir=${root_dir}/libs/shared/app/golang
module_path=github.com/novassist-ai/mycs-node/libs/shared/app/golang

build_dir=${root_dir}/.build
rm -fr ${build_dir}/bin

if [[ $action == *:clean-all:* ]]; then
  rm -fr ${build_dir}
fi
release_dir=${build_dir}/releases
mkdir -p ${release_dir}

build_os=$(go env GOOS)
build_arch=$(go env GOARCH)

function build() {

  local os=$1
  local arch=$2
  local srcpath=$3
  local outfile=$4
  local build_version=$5
  local build_timestamp=$6

  if [[ $os == windows ]]; then
    outfile="${outfile}.exe"
  fi

  mkdir -p ${release_dir}/${os}_${arch}
  pushd ${release_dir}/${os}_${arch}

  local out_dir=$(dirname $srcpath)/.out
  mkdir -p $out_dir
  pushd $out_dir

  versionFlags="-X \"${module_path}/internal.Version=$build_version\" -X \"${module_path}/internal.BuildTimestamp=$build_timestamp\""

  if [[ $action == *:dev:* ]]; then
    GOOS=$os GOARCH=$arch go build -ldflags "$versionFlags" -o $outfile $srcpath
  else
    if [[ $build_os == linux ]]; then
      GOOS=$os GOARCH=$arch CGO_ENABLED=0 go build -ldflags "-s -w $versionFlags" -o $outfile $srcpath
    else
      GOOS=$os GOARCH=$arch go build -ldflags "-s -w $versionFlags" -o $outfile $srcpath
    fi
  fi
  mv $out_dir/* ${release_dir}/${os}_${arch}

  popd
  rm -fr $out_dir

  zip -ru ${release_dir}/mycs-cookbook-utils_${os}_${arch}.zip .
  popd
}

if [[ $action == *:dev:* ]]; then
  build_version=dev
  build_timestamp=$(date +'%B %d, %Y at %H:%M %Z')

  os=$build_os
  arch=$build_arch
  for srcpath in $(find ${golang_dir}/cmd/* -type d -print); do
    build "$os" "$arch" \
      "${srcpath}" \
      $(basename $srcpath) \
      "$build_version" "$build_timestamp"
  done

else
  tag=${GITHUB_REF/refs\/tags\//}
  build_version=${tag:-0.0.0}
  build_timestamp=$(date +'%B %d, %Y at %H:%M %Z')

  if [[ -n $os && -n $arch ]]; then
    for srcpath in $(find ${golang_dir}/cmd/* -type d -print); do
      build "$os" "$arch" \
        "${srcpath}" \
        $(basename $srcpath) \
        "$build_version" "$build_timestamp"
    done
  else
    echo "Target OS and ARCH arguments missing."
    exit 1
  fi
fi

ln -sfn ${release_dir}/${build_os}_${build_arch} ${build_dir}/bin
