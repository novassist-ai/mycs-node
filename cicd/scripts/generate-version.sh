#!/bin/bash

# Versioning and branch strategy:
#
# branch
# ------
#
# f3    |                            *---------------------------*
#                                   /                             \
# f2    |-----------------*        /                               \
#                          \      /                                 \
# f1    |----*              \    /                                   \
#             \              \  /                                     \
# dev   |-- 0.0.0-dev1 --- 0.0.0-dev2 --------------- 0.1.0-dev1 --- 0.1.0-dev2 ---> dev releases
#                              \                       /                \
# main  |-------------------- 0.0.0 --------------- 0.0.1 -------------0.1.0-------> production releases
#                                \                   /
# 0.0.1 | builds for patch 0.0.1  *---------------0.0.1-patch1
#                                  \               /
# fix   |                           *-------------*
#

set +e
which git >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo -e "\nERROR! The Git CLI is required."
  exit 1
fi

set -euo pipefail

function usage() {
  echo -e "\nUSAGE: generate-version.sh [options]\n"
  echo -e "  -n|--name [NAME]        the name of the application"
  echo -e "  -v|--version [VERSION]  the major version number (default: 0)"
  echo -e "  -b|--branch [BRANCH]    the branch name (default: dev)"
  echo -e "  -d|--debug              enable trace output"
  echo -e "  -h|--help               show this help"
}

major_version=0
branch=dev
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version)
      major_version=$2
      shift
      ;;
    -b|--branch)
      branch=$2
      shift
      ;;
    -n|--name)
      name=$2
      shift
      ;;
    -d|--debug)
      set -x
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo -e "\nERROR! Unknown option \"$1\"."
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z $name ]]; then
  echo -e "\nERROR! The name of the app is required."
  usage
  exit 1
fi

# Tests queries for git refs
#
# git for-each-ref \
#   --sort=-creatordate \
#   --format='%(creatordate:format:%Y-%m-%d %H:%M) %(refname)'
#

refs=$(git for-each-ref \
  --sort=-creatordate \
  --format='%(refname)'
)

# ------ sample output ------
#
# set +e
# read -r -d '' refs << EOM
# refs/tags/smart_reader_0.1.1
# refs/tags/smart_reader_0.1.0-patch1
# refs/remotes/origin/main
# refs/tags/smart_reader_0.2.0-dev0
# refs/remotes/origin/dev
# refs/tags/smart_reader_0.1.0
# refs/tags/smart_reader_0.1.0-dev3
# refs/tags/smart_reader_0.0.3
# refs/tags/smart_reader_0.1.0-dev2
# refs/tags/smart_reader_0.1.0-dev1
# refs/tags/smart_reader_0.1.0-dev0
# refs/tags/smart_reader_0.0.2
# refs/tags/smart_reader_0.0.1
# refs/tags/smart_reader_0.0.0
# refs/tags/smart_reader_0.0.0-dev2
# refs/tags/smart_reader_0.0.0-dev1
# EOM
# set -e

latest_prod_release_ver=$(echo "$refs" \
  | awk "/refs\/tags\/${name}_[0-9]+\.[0-9]+\.[0-9]+$/{ print }" \
  | head -1)
# Latest prod release for current major (for dev-branch logic).
latest_prod_release_ver_for_major=$(echo "$refs" \
  | awk "/refs\/tags\/${name}_${major_version}\.[0-9]+\.[0-9]+$/{ print }" \
  | head -1)

# Latest dev tag for this major: max (minor, patch, dev N). Ensures e.g. 1.1.0-dev25
# is chosen over 1.0.0-dev* when prod is still 1.0.x so main releases follow the active dev line.
dev_tags_this_major=$(echo "$refs" \
  | awk "/refs\/tags\/${name}_${major_version}\.[0-9]+\.[0-9]+-dev[0-9]+$/{ print }")
latest_dev_build_ver=''
if [[ -n $dev_tags_this_major ]]; then
  latest_dev_build_ver=$(echo "$dev_tags_this_major" \
    | while read -r ref; do
        [[ -z $ref ]] && continue
        base=$(basename "$ref")
        ver_part=${base#${name}_}
        core=${ver_part%-dev*}
        dev_num=${ver_part#*-dev}
        minor=$(echo "$core" | cut -d '.' -f2)
        patch=$(echo "$core" | cut -d '.' -f3)
        printf '%s\t%s\t%s\t%s\n' "$minor" "$patch" "$dev_num" "$ref"
      done \
    | sort -t$'\t' -k1,1n -k2,2n -k3,3n \
    | tail -1 \
    | cut -f4-)
fi
# If no dev tag for this major, fall back to any dev tag (for major bump logic).
if [[ -z $latest_dev_build_ver ]]; then
  latest_dev_build_ver=$(echo "$refs" \
    | awk "/refs\/tags\/${name}_[0-9]+\.[0-9]+\.[0-9]+-dev[0-9]+$/{ print }" \
    | head -1)
fi

latest_release=${latest_prod_release_ver#refs/tags/*}
if [[ -n $latest_prod_release_ver ]]; then
  release_ver_part="${latest_release#${name}_}"
  release_major=$(echo "$release_ver_part" | cut -d '.' -f1)
  release_minor=$(echo "$release_ver_part" | cut -d '.' -f2)
  release_patch=$(echo "$release_ver_part" | cut -d '.' -f3)
  next_patch=$((release_patch + 1))
  latest_release_patch_branch="patch_${name}_${release_major}.${release_minor}.${next_patch}"
  patch_release_tag="${name}_${release_major}.${release_minor}.${next_patch}"
else
  latest_release_patch_branch='none'
  patch_release_tag=''
fi

latest_patch_build_ver=$(echo "$refs" \
  | awk "/refs\/tags\/${patch_release_tag}-patch[0-9]+\$/{ print }" \
  | head -1)

# Parse version part from a full tag basename (handles hyphenated app names).
# e.g. mycs-node-image_0.1.0-dev3 → ver_part=0.1.0-dev3
tag_ver_part() {
  local base
  base=$(basename "$1")
  echo "${base#${name}_}"
}

# Dev-style tag (X.Y.Z-devN): used for branch "dev" or any branch matching ^.*_dev$
if [[ $branch == dev || $branch =~ _dev$ ]]; then
  if [[ -z $latest_dev_build_ver ]]; then
    build_tag="${major_version}.0.0-dev0"
  else
    tag_version_part=$(tag_ver_part "$latest_dev_build_ver")
    tag_version_core=${tag_version_part%-dev*}
    tag_major=$(echo "$tag_version_core" | cut -d '.' -f1)
    if [[ -n $tag_major && $major_version -gt $tag_major ]]; then
      build_tag="${major_version}.0.0-dev0"
    else
      build_minor=$(echo "$tag_version_core" | cut -d '.' -f2)
      build_number=${tag_version_part#*-dev}

      if [[ -n $latest_prod_release_ver_for_major ]]; then
        release_ver_part=$(tag_ver_part "$latest_prod_release_ver_for_major")
        release_minor=$(echo "$release_ver_part" | cut -d '.' -f2)
      else
        release_minor=
      fi
      if [[ -n $release_minor && $build_minor -le $release_minor ]]; then
        build_minor=$((release_minor + 1))
        build_number=0
      else
        build_number=$((build_number + 1))
      fi
      build_tag="${major_version}.${build_minor}.0-dev${build_number}"
      # If this tag already exists (e.g. created in a previous run), increment until we get a new one
      while echo "$refs" | grep -q "refs/tags/${name}_${build_tag}$"; do
        build_number=$((build_number + 1))
        build_tag="${major_version}.${build_minor}.0-dev${build_number}"
      done
    fi
  fi
  # For branches matching *_dev (but not exactly "dev"), add unique postfix: -<branch>-<YYYYMMDDHHmmss>
  if [[ $branch != dev && $branch =~ _dev$ ]]; then
    branch_sanitized=$(echo "$branch" | sed 's|/|-|g')
    unique_ts=$(date +%Y%m%d%H%M%S)
    echo "${name}_fbr-${branch_sanitized}-${unique_ts}"
  else
    echo "${name}_${build_tag}"
  fi

elif [[ $branch == $latest_release_patch_branch ]]; then
  if [[ -z $latest_patch_build_ver ]]; then
    echo "${patch_release_tag}-patch0"
  else
    patch_ver_part=$(tag_ver_part "$latest_patch_build_ver")
    build_number=${patch_ver_part#*-patch}
    build_number=$((build_number + 1))
    echo "${patch_release_tag}-patch${build_number}"
  fi

elif [[ $branch == patch_${name}_* ]]; then
  branch_version="${branch#patch_${name}_}"
  if [[ $branch_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    branch_version_escaped=$(echo "$branch_version" | sed 's/\./\\./g')
    existing_patch_tags=$(echo "$refs" | awk "/refs\/tags\/${name}_${branch_version_escaped}-patch[0-9]+\$/{ print }")
    if [[ -z $existing_patch_tags ]]; then
      echo "${name}_${branch_version}-patch0"
    else
      build_number=$(echo "$existing_patch_tags" | sed -n "s|.*-patch\\([0-9]*\)\$|\1|p" | sort -n | tail -1)
      build_number=$((build_number + 1))
      echo "${name}_${branch_version}-patch${build_number}"
    fi
  fi

elif [[ $branch == main ]]; then
  # Main commits are merged from dev or a patch branch.
  # For a two-parent merge, the second parent is the tip of the merged branch.
  # For a single-parent commit (squash merge or direct push), we cannot detect
  # the source from the graph; we treat it as a release from dev and use the
  # latest dev build version.
  set +e
  second_parent=$(git rev-parse HEAD^2 2>/dev/null)
  if [[ $? -eq 0 && -n $second_parent ]]; then
    possible_merged_commit=$second_parent
  else
    possible_merged_commit=''
  fi
  if [[ -n $possible_merged_commit ]]; then
    commit_from_branch=$(git branch -r --contains $possible_merged_commit | grep -v main | xargs)
  else
    commit_from_branch=''
  fi
  set -e

  # Main can be merged only from dev or a patch branch.
  # Patch branches are named patch_<name>_X.Y.Z where X.Y.Z is the next patch
  # version (e.g. patch_smart_workflow_1.2.1 when branching off 1.2.0).

  if [[ $commit_from_branch =~ origin/dev ]]; then
    echo "$(basename "$latest_dev_build_ver" | sed 's/-dev[0-9]*$//')"

  elif [[ -n $commit_from_branch && $commit_from_branch =~ origin/${latest_release_patch_branch} ]]; then
    echo "${latest_release_patch_branch#patch_}"

  elif [[ -z $possible_merged_commit || -z $commit_from_branch ]]; then
    # Single-parent commit (squash merge or direct push): cannot detect merge source.
    # If there are patch builds for the next release line, assume release from that patch branch.
    if [[ -n $latest_patch_build_ver && -n $patch_release_tag ]]; then
      echo "$patch_release_tag"
    elif [[ -n $latest_dev_build_ver ]]; then
      echo "$(basename "$latest_dev_build_ver" | sed 's/-dev[0-9]*$//')"
    else
      echo -e "\nERROR! Cannot determine release version (no dev build tag or patch build tag found)."
      exit 1
    fi

  else
    echo -e "\nERROR! Source branch from which last change was"
    echo -e "         merged to main is not consistent with the"
    echo -e "         release strategy. This needs to be fixed."
    exit 1
  fi
fi
