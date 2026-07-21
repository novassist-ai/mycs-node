#!/bin/bash

# Deletes GitHub Actions workflow run logs older than a given date for the current repo.
# Uses DELETE .../actions/runs/{run_id}/logs to remove logs only (run record remains).
# Only completed runs are considered; logs for in-progress runs cannot be deleted.
# Requires: GitHub CLI (gh) logged in, or GITHUB_TOKEN with repo scope (Actions write for fine-grained PATs).
# Repository is taken from git remote origin.

set -euo pipefail

usage() {
  echo "USAGE: cleanup_workflow_logs.sh ( -D|--date YYYY-MM-DD ) [options]"
  echo ""
  echo "  -D|--date YYYY-MM-DD  delete logs for workflow runs created before this date"
  echo "  --delete-runs         delete the entire run (and its logs) instead of logs only"
  echo "  -y|--yes              do not ask for confirmation"
  echo "  -d|--dry-run          print what would be deleted, do not delete"
  echo "  -h|--help             show this help"
}

cutoff_date=""
delete_runs=false
yes_mode=false
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -D|--date)
      cutoff_date="$2"
      shift
      ;;
    --delete-runs)
      delete_runs=true
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

# Validate date and build ISO for comparison (API returns created_at like 2024-01-15T12:00:00Z)
cutoff_iso="${cutoff_date}T00:00:00Z"
if ! date -j -f "%Y-%m-%d" "${cutoff_date}" "+%Y-%m-%d" &>/dev/null; then
  if ! date -d "${cutoff_date}" "+%Y-%m-%d" &>/dev/null; then
    echo "ERROR: Invalid date '${cutoff_date}'. Use YYYY-MM-DD."
    exit 1
  fi
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

echo "Cutoff date: ${cutoff_date} (runs created before this will have logs deleted)"
echo "Repository: ${repo}"
[[ "$delete_runs" == true ]] && echo "Mode: delete entire run (and logs)"
[[ "$delete_runs" == false ]] && echo "Mode: delete logs only (run record kept)"

# List workflow run IDs with created_at < cutoff. Explicit pagination so all pages are fetched.
list_run_ids_older_than() {
  local repo=$1
  local cutoff=$2
  local page=1
  local count
  if command -v gh &>/dev/null; then
    while true; do
      resp=$(gh api "repos/${repo}/actions/runs?per_page=100&page=${page}&status=completed" 2>/dev/null || true)
      [[ -z "${resp}" ]] && break
      echo "${resp}" | jq -r --arg cutoff "${2}" '
        (.workflow_runs // [])[] | select(.created_at != null) | select(.created_at < $cutoff) | "\(.id)\t\(.created_at)"
      ' 2>/dev/null || true
      count=$(echo "${resp}" | jq -r '(.workflow_runs // []) | length' 2>/dev/null || echo "0")
      [[ "${count}" -lt 100 ]] && break
      page=$((page + 1))
    done
  elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
    export CUTOFF_ISO="${2}"
    while true; do
      resp=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${repo}/actions/runs?per_page=100&page=${page}&status=completed" 2>/dev/null || true)
      echo "${resp}" | python3 -c "
import sys, json, os
cutoff = os.environ.get('CUTOFF_ISO', '')
try:
    data = json.load(sys.stdin)
    runs = data.get('workflow_runs') or []
    for r in runs:
        ct = r.get('created_at') or ''
        if ct and cutoff and ct < cutoff:
            print(r.get('id', ''), ct, sep='\t')
except Exception:
    pass
" 2>/dev/null
      count=$(echo "${resp}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('workflow_runs',[])))" 2>/dev/null || echo "0")
      [[ "${count}" -lt 100 ]] && break
      page=$((page + 1))
    done
  else
    echo "ERROR: Need either 'gh' CLI (logged in) or GITHUB_TOKEN to list workflow runs." >&2
    return 1
  fi
}

# Delete logs for one run (or delete the run if --delete-runs). Reports errors on failure.
# run_date is optional; when set, shown in output (e.g. 2024-01-15T12:00:00Z).
delete_run_logs_or_run() {
  local repo=$1
  local run_id=$2
  local run_date=${3:-}
  local date_suffix=""
  [[ -n "${run_date}" ]] && date_suffix=" (${run_date})"
  if [[ "$dry_run" == true ]]; then
    if [[ "$delete_runs" == true ]]; then
      echo "  [dry-run] Would delete workflow run: ${run_id}${date_suffix}"
    else
      echo "  [dry-run] Would delete logs for run: ${run_id}${date_suffix}"
    fi
    return
  fi
  if command -v gh &>/dev/null; then
    if [[ "$delete_runs" == true ]]; then
      if gh api -X DELETE "repos/${repo}/actions/runs/${run_id}" 2>/dev/null; then
        echo "  Deleted run: ${run_id}${date_suffix}"
      else
        echo "  ERROR: Failed to delete run ${run_id}${date_suffix} (check permissions: repo scope or actions:write)" >&2
      fi
    else
      if gh api -X DELETE "repos/${repo}/actions/runs/${run_id}/logs" 2>/dev/null; then
        echo "  Deleted logs for run: ${run_id}${date_suffix}"
      else
        echo "  ERROR: Failed to delete logs for run ${run_id}${date_suffix} (run must be completed; check token has repo/Actions write)" >&2
      fi
    fi
  elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
    local code body
    if [[ "$delete_runs" == true ]]; then
      body=$(curl -sS -w "\n%{http_code}" -X DELETE \
        -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${repo}/actions/runs/${run_id}")
      code=$(echo "${body}" | tail -1)
      if [[ "$code" == "204" ]]; then
        echo "  Deleted run: ${run_id}${date_suffix}"
      else
        echo "  ERROR: Delete run ${run_id}${date_suffix} returned HTTP ${code}" >&2
      fi
    else
      body=$(curl -sS -w "\n%{http_code}" -X DELETE \
        -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${repo}/actions/runs/${run_id}/logs")
      code=$(echo "${body}" | tail -1)
      if [[ "$code" == "204" ]]; then
        echo "  Deleted logs for run: ${run_id}${date_suffix}"
      else
        echo "  ERROR: Delete logs for run ${run_id}${date_suffix} returned HTTP ${code} (run must be completed; token needs repo/Actions write)" >&2
      fi
    fi
  fi
}

echo "Listing completed workflow runs created before ${cutoff_date}..."
run_entries=()
while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  run_entries+=("${line}")
done < <(CUTOFF_ISO="${cutoff_iso}" list_run_ids_older_than "${repo}" "${cutoff_iso}")

if [[ ${#run_entries[@]} -eq 0 ]]; then
  echo "No workflow runs found older than ${cutoff_date}."
  exit 0
fi

echo "Found ${#run_entries[@]} run(s) to process."

if [[ "$dry_run" == true ]]; then
  for entry in "${run_entries[@]}"; do
    run_id="${entry%%$'\t'*}"
    run_date="${entry#*$'\t'}"
    delete_run_logs_or_run "${repo}" "${run_id}" "${run_date}"
  done
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

for entry in "${run_entries[@]}"; do
  run_id="${entry%%$'\t'*}"
  run_date="${entry#*$'\t'}"
  delete_run_logs_or_run "${repo}" "${run_id}" "${run_date}"
done

echo "Cleanup complete."
