#!/bin/bash

# Deletes GitHub releases and git tags older than a given date.
# Retention follows generate-version.sh channels, per app prefix:
#   prod  name_X.Y.Z
#   dev   name_X.Y.Z-devN
# Always keeps the N newest of each channel per prefix (default N=1), so a
# cutoff that covers every match still leaves the latest prod and dev tags.
# Prefixes are inferred from tag names (name_…) when -p is not set.
# Uses release published_at for releases; uses tagger/creator date for tags.
# Fetches origin tags first so remote-only tags are included.
# Requires: GitHub CLI (gh) logged in, or GITHUB_TOKEN env and curl.
# Repository is taken from git remote origin.

set -euo pipefail

usage() {
  echo "USAGE: cleanup_releases.sh ( -D|--date YYYY-MM-DD ) [options]"
  echo ""
  echo "  -D|--date YYYY-MM-DD  delete releases and tags older than this date"
  echo "  -p|--prefix NAME      only delete tags/releases whose name starts with NAME_ (e.g. smart_workflow)"
  echo "  -k|--keep N           keep N newest prod and N newest dev tags per prefix (default: 1)"
  echo "  -r|--releases-only    delete only GitHub releases (and their tags)"
  echo "  -t|--tags-only        delete only tags older than date (no release listing)"
  echo "  -y|--yes              do not ask for confirmation"
  echo "  -d|--dry-run          print what would be deleted, do not delete"
  echo "  -h|--help             show this help"
}

cutoff_date=""
prefix=""
keep_count=1
releases_only=false
tags_only=false
yes_mode=false
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -D|--date)
      cutoff_date="$2"
      shift
      ;;
    -p|--prefix)
      prefix="$2"
      shift
      ;;
    -k|--keep)
      keep_count="$2"
      shift
      ;;
    -r|--releases-only)
      releases_only=true
      ;;
    -t|--tags-only)
      tags_only=true
      ;;
    -y|--yes)
      yes_mode=true
      ;;
    -d|--dry-run)
      dry_run=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option \"$1\"."
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z "${cutoff_date}" ]]; then
  echo "ERROR: -D|--date YYYY-MM-DD is required."
  usage
  exit 1
fi

if ! [[ "${keep_count}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: -k|--keep must be a non-negative integer (got '${keep_count}')."
  exit 1
fi

# Validate date format (YYYY-MM-DD) and get epoch (portable: macOS date -j, Linux date -d)
cutoff_epoch=""
if cutoff_epoch=$(date -j -f "%Y-%m-%d" "${cutoff_date}" "+%s" 2>/dev/null); then
  :
elif cutoff_epoch=$(date -d "${cutoff_date}" "+%s" 2>/dev/null); then
  :
else
  echo "ERROR: Invalid date '${cutoff_date}'. Use YYYY-MM-DD."
  exit 1
fi
cutoff_iso="${cutoff_date}T00:00:00Z"

if [[ "$releases_only" == true && "$tags_only" == true ]]; then
  echo "ERROR: Cannot use both --releases-only and --tags-only."
  usage
  exit 1
fi

# Repository from origin
origin_url=$(git config --get remote.origin.url 2>/dev/null || true)
if [[ -z "${origin_url}" ]]; then
  echo "ERROR: No git remote 'origin' found."
  exit 1
fi
if [[ "${origin_url}" =~ ^https://github\.com/([^/]+)/([^/.]+) ]]; then
  repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
elif [[ "${origin_url}" =~ ^git@github\.com:([^/]+)/([^/.]+)\.git$ ]]; then
  repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
else
  echo "ERROR: Could not parse origin URL (expected github.com). origin=${origin_url}"
  exit 1
fi

echo "Cutoff date: ${cutoff_date} (releases/tags before this will be deleted)"
[[ -n "${prefix}" ]] && echo "Prefix filter: ${prefix}_ (only tags/releases starting with this)"
echo "Keep newest: ${keep_count} prod + ${keep_count} dev per app prefix (semver)"
echo "Repository: ${repo}"

# Include remote-only tags in local refs so date listing is complete
echo "Fetching tags from origin..."
git fetch origin --tags 2>/dev/null || true

# Normalize a date string to ISO for lexicographic compare (YYYY-MM-DD or full ISO)
to_iso() {
  local d=$1
  if [[ "${d}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "${d}T00:00:00Z"
  else
    # Strip fractional seconds if present; keep trailing Z or offset
    echo "${d}" | sed -E 's/\.[0-9]+//'
  fi
}

# True if tag matches optional prefix filter
matches_prefix() {
  local tag=$1
  if [[ -n "${prefix}" && "${tag}" != "${prefix}_"* ]]; then
    return 1
  fi
  return 0
}

# List all GitHub releases as: tag_name<TAB>iso_date
list_all_releases() {
  local repo=$1
  if command -v gh &>/dev/null; then
    gh api --paginate "repos/${repo}/releases" -q '
      .[] | select((.published_at // .created_at) != null)
      | "\(.tag_name)\t\(.published_at // .created_at)"
    ' 2>/dev/null || true
  elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
    local page=1
    while true; do
      url="https://api.github.com/repos/${repo}/releases?per_page=100&page=${page}"
      resp=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" "${url}" 2>/dev/null || true)
      echo "${resp}" | python3 -c "
import sys, json
try:
    releases = json.load(sys.stdin)
    if not isinstance(releases, list):
        sys.exit(0)
    for r in releases:
        pt = r.get('published_at') or r.get('created_at') or ''
        tag = r.get('tag_name') or ''
        if pt and tag:
            print(f'{tag}\t{pt}')
except Exception:
    pass
" 2>/dev/null
      count=$(echo "${resp}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d, list) else 0)" 2>/dev/null || echo "0")
      [[ "${count}" -lt 100 ]] && break
      page=$((page + 1))
    done
  else
    echo "ERROR: Need either 'gh' CLI (logged in) or GITHUB_TOKEN to list releases." >&2
    return 1
  fi
}

# Find release id by tag (works for published and draft; paginates list fallback)
find_release_id_by_tag() {
  local repo=$1
  local tag=$2
  local token=$3
  local resp http_code id page
  resp=$(curl -sS -w "\n%{http_code}" -H "Authorization: token ${token}" \
    "https://api.github.com/repos/${repo}/releases/tags/${tag}" 2>/dev/null || true)
  http_code=$(echo "${resp}" | tail -1)
  resp=$(echo "${resp}" | sed '$d')
  id=$(echo "${resp}" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('id',''))" 2>/dev/null)
  if [[ -n "${id}" && "${http_code}" == "200" ]]; then
    echo "${id}"
    return
  fi
  page=1
  while true; do
    resp=$(curl -sS -H "Authorization: token ${token}" \
      "https://api.github.com/repos/${repo}/releases?per_page=100&page=${page}" 2>/dev/null || true)
    id=$(printf '%s' "${resp}" | TAG="${tag}" python3 -c "
import sys, json, os
tag = os.environ.get('TAG', '')
try:
    releases = json.load(sys.stdin)
    if not isinstance(releases, list):
        sys.exit(0)
    for r in releases:
        if r.get('tag_name') == tag:
            print(r['id'])
            break
except Exception:
    pass
" 2>/dev/null)
    if [[ -n "${id}" ]]; then
      echo "${id}"
      return
    fi
    count=$(printf '%s' "${resp}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d, list) else 0)" 2>/dev/null || echo "0")
    [[ "${count}" -lt 100 ]] && break
    page=$((page + 1))
  done
}

# Delete a single release and its tag (handles published and draft)
delete_release_and_tag() {
  local repo=$1
  local tag_name=$2
  local do_release=$3
  local do_tag=$4

  if [[ "$do_release" == true ]]; then
    if command -v gh &>/dev/null; then
      release_id=$(gh api --paginate "repos/${repo}/releases" -q ".[] | select(.tag_name==\"${tag_name}\") | .id" 2>/dev/null | head -1 || true)
      if [[ -n "${release_id}" ]]; then
        if [[ "$dry_run" == true ]]; then
          echo "  [dry-run] Would delete GitHub release: ${tag_name}"
        else
          gh release delete "${tag_name}" --repo "${repo}" --yes 2>/dev/null || \
            gh api -X DELETE "repos/${repo}/releases/${release_id}" 2>/dev/null
          echo "  Deleted GitHub release: ${tag_name}"
        fi
      fi
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
      release_id=$(find_release_id_by_tag "${repo}" "${tag_name}" "${GITHUB_TOKEN}")
      if [[ -n "${release_id}" ]]; then
        if [[ "$dry_run" == true ]]; then
          echo "  [dry-run] Would delete GitHub release: ${tag_name}"
        else
          curl -sS -X DELETE -H "Authorization: token ${GITHUB_TOKEN}" \
            "https://api.github.com/repos/${repo}/releases/${release_id}" >/dev/null
          echo "  Deleted GitHub release: ${tag_name}"
        fi
      fi
    fi
  fi

  if [[ "$do_tag" == true ]]; then
    if [[ "$dry_run" == true ]]; then
      echo "  [dry-run] Would delete tag (local and remote): ${tag_name}"
    else
      if git rev-parse "refs/tags/${tag_name}" &>/dev/null; then
        git tag -d "${tag_name}"
        echo "  Deleted local tag: ${tag_name}"
      fi
      if git ls-remote --exit-code origin "refs/tags/${tag_name}" &>/dev/null; then
        git push origin --delete "refs/tags/${tag_name}"
        echo "  Deleted remote tag: ${tag_name}"
      fi
    fi
  fi
}

# Collect matching tags/releases as iso|tag lines (Bash 3 compatible; no assoc arrays).
# If the same tag appears twice, keep the later ISO date.
dated_entries=()

upsert_dated_entry() {
  local tag=$1
  local iso=$2
  local i entry existing_iso existing_tag
  for i in "${!dated_entries[@]}"; do
    entry="${dated_entries[$i]}"
    existing_iso="${entry%%|*}"
    existing_tag="${entry#*|}"
    if [[ "${existing_tag}" == "${tag}" ]]; then
      if [[ "${iso}" > "${existing_iso}" ]]; then
        dated_entries[$i]="${iso}|${tag}"
      fi
      return
    fi
  done
  dated_entries+=("${iso}|${tag}")
}

# ---- Releases (all matching prefix; retention needs full set) ----
if [[ "$tags_only" != true ]]; then
  echo "Listing GitHub releases..."
  if ! command -v gh &>/dev/null && [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "ERROR: Need either 'gh' CLI (logged in) or GITHUB_TOKEN to list releases."
    exit 1
  fi
  while IFS=$'\t' read -r tag iso_raw; do
    [[ -z "${tag}" ]] && continue
    matches_prefix "${tag}" || continue
    upsert_dated_entry "${tag}" "$(to_iso "${iso_raw}")"
  done < <(list_all_releases "${repo}")
fi

# ---- Tags (local after fetch; all matching prefix) ----
if [[ "$releases_only" != true ]]; then
  echo "Listing tags (local + fetched from origin)..."
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    tag="${line%% *}"
    d="${line##* }"
    if [[ -z "${tag}" || -z "${d}" ]]; then continue; fi
    matches_prefix "${tag}" || continue
    upsert_dated_entry "${tag}" "$(to_iso "${d}")"
  done < <(git for-each-ref --format='%(refname:short) %(creatordate:short)' refs/tags 2>/dev/null || true)
fi

if [[ ${#dated_entries[@]} -eq 0 ]]; then
  echo "No tags/releases found${prefix:+ matching prefix ${prefix}_}."
  exit 0
fi

# Parse generate-version.sh-style tags:
#   prod  PREFIX_X.Y.Z
#   dev   PREFIX_X.Y.Z-devN
#   patch PREFIX_X.Y.Z-patchN  (not retained by default; only prod+dev)
# Sets: _parse_prefix _parse_kind (prod|dev|patch|other)
#        _parse_maj _parse_min _parse_pat _parse_build
parse_version_tag() {
  local tag=$1
  _parse_prefix=""
  _parse_kind=other
  _parse_maj=0
  _parse_min=0
  _parse_pat=0
  _parse_build=0
  if [[ "${tag}" =~ ^(.+)_([0-9]+)\.([0-9]+)\.([0-9]+)-dev([0-9]+)$ ]]; then
    _parse_prefix="${BASH_REMATCH[1]}"
    _parse_kind=dev
    _parse_maj="${BASH_REMATCH[2]}"
    _parse_min="${BASH_REMATCH[3]}"
    _parse_pat="${BASH_REMATCH[4]}"
    _parse_build="${BASH_REMATCH[5]}"
  elif [[ "${tag}" =~ ^(.+)_([0-9]+)\.([0-9]+)\.([0-9]+)-patch([0-9]+)$ ]]; then
    _parse_prefix="${BASH_REMATCH[1]}"
    _parse_kind=patch
    _parse_maj="${BASH_REMATCH[2]}"
    _parse_min="${BASH_REMATCH[3]}"
    _parse_pat="${BASH_REMATCH[4]}"
    _parse_build="${BASH_REMATCH[5]}"
  elif [[ "${tag}" =~ ^(.+)_([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    _parse_prefix="${BASH_REMATCH[1]}"
    _parse_kind=prod
    _parse_maj="${BASH_REMATCH[2]}"
    _parse_min="${BASH_REMATCH[3]}"
    _parse_pat="${BASH_REMATCH[4]}"
  fi
}

# Append val to bash array named by first arg if not already present (Bash 3).
add_unique() {
  local arr_name=$1
  local val=$2
  local existing i
  eval "local len=\${#${arr_name}[@]}"
  i=0
  while [[ $i -lt $len ]]; do
    eval "existing=\${${arr_name}[$i]}"
    [[ "${existing}" == "${val}" ]] && return
    i=$((i + 1))
  done
  eval "${arr_name}+=(\"\${val}\")"
}

# Protect N newest prod + N newest dev per app prefix (semver), matching
# generate-version.sh channel names. Unversioned tags: keep N newest by date.
protected=()
app_prefixes=()

for entry in "${dated_entries[@]}"; do
  tag="${entry#*|}"
  parse_version_tag "${tag}"
  if [[ "${_parse_kind}" == prod || "${_parse_kind}" == dev ]]; then
    add_unique app_prefixes "${_parse_prefix}"
  fi
done

if [[ "${keep_count}" -gt 0 ]]; then
  for app in "${app_prefixes[@]:-}"; do
    # Prod: PREFIX_X.Y.Z — highest semver
    while IFS= read -r tag; do
      [[ -z "${tag}" ]] && continue
      add_unique protected "${tag}"
    done < <(
      for entry in "${dated_entries[@]}"; do
        tag="${entry#*|}"
        parse_version_tag "${tag}"
        [[ "${_parse_kind}" == prod && "${_parse_prefix}" == "${app}" ]] || continue
        printf '%d\t%d\t%d\t%s\n' "${_parse_maj}" "${_parse_min}" "${_parse_pat}" "${tag}"
      done | sort -t$'\t' -k1,1n -k2,2n -k3,3n | tail -n "${keep_count}" | cut -f4-
    )

    # Dev: PREFIX_X.Y.Z-devN — highest semver then build N
    while IFS= read -r tag; do
      [[ -z "${tag}" ]] && continue
      add_unique protected "${tag}"
    done < <(
      for entry in "${dated_entries[@]}"; do
        tag="${entry#*|}"
        parse_version_tag "${tag}"
        [[ "${_parse_kind}" == dev && "${_parse_prefix}" == "${app}" ]] || continue
        printf '%d\t%d\t%d\t%d\t%s\n' "${_parse_maj}" "${_parse_min}" "${_parse_pat}" "${_parse_build}" "${tag}"
      done | sort -t$'\t' -k1,1n -k2,2n -k3,3n -k4,4n | tail -n "${keep_count}" | cut -f5-
    )
  done

  # Non version-channel tags (fbr-*, odd names): keep N newest by date overall
  other_count=0
  while IFS= read -r entry; do
    [[ -z "${entry}" ]] && continue
    tag="${entry#*|}"
    parse_version_tag "${tag}"
    [[ "${_parse_kind}" == other ]] || continue
    add_unique protected "${tag}"
    other_count=$((other_count + 1))
    [[ "${other_count}" -ge "${keep_count}" ]] && break
  done < <(printf '%s\n' "${dated_entries[@]}" | LC_ALL=C sort -t'|' -k1 -r)
fi

if [[ ${#protected[@]} -gt 0 ]]; then
  echo "Retaining ${#protected[@]} tag(s)/release(s) (latest prod+dev per prefix): ${protected[*]}"
fi

is_protected() {
  local tag=$1 p
  for p in "${protected[@]:-}"; do
    [[ "${p}" == "${tag}" ]] && return 0
  done
  return 1
}

# Delete candidates: older than cutoff and not protected
to_delete=()
for entry in "${dated_entries[@]}"; do
  iso="${entry%%|*}"
  tag="${entry#*|}"
  [[ "${iso}" < "${cutoff_iso}" ]] || continue
  is_protected "${tag}" && continue
  to_delete+=("${tag}")
done
total=${#to_delete[@]}

older_count=0
for entry in "${dated_entries[@]}"; do
  iso="${entry%%|*}"
  [[ "${iso}" < "${cutoff_iso}" ]] && older_count=$((older_count + 1))
done
echo "Matching tags/releases: ${#dated_entries[@]} (older than cutoff: ${older_count}, retained: ${#protected[@]}, to delete: ${total})"

if [[ ${total} -eq 0 ]]; then
  echo "Nothing to delete."
  exit 0
fi

echo "Total tags/releases to delete: ${total}"
if [[ "$dry_run" == true ]]; then
  for t in "${to_delete[@]}"; do echo "  - $t"; done
  echo "Dry run complete."
  exit 0
fi

if [[ "$yes_mode" != true ]]; then
  read -r -p "Continue? [y/N] " reply
  if [[ ! "${reply}" =~ ^[yY]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

for tag_name in "${to_delete[@]}"; do
  echo "Processing: ${tag_name}"
  delete_release_and_tag "${repo}" "${tag_name}" true true
done

echo "Cleanup complete."
