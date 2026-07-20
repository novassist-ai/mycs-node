# CI/CD scripts

| Script | Purpose |
|--------|---------|
| [`generate-version.sh`](#generate-versionsh) | Compute next `name_X.Y.Z[-devN\|-patchN]` git tag for a branch |
| [`bump-homebrew-vpn-node-builder.sh`](#bump-homebrew-vpn-node-buildersh) | Update `novassist-ai/homebrew-tap` formula `url`/`sha256` for a `vpnb_X.Y.Z` tag |
| [`cleanup_releases.sh`](#cleanup_releasessh) | Delete GitHub releases/tags older than a cutoff; keep latest prod+dev per app prefix |
| [`cleanup_workflow_logs.sh`](#cleanup_workflow_logssh) | Delete GitHub Actions workflow run logs (or runs) older than a cutoff |

All scripts are intended to be run from a git checkout of this repo (they use `git` and, where noted, `origin`).

---

## `generate-version.sh`

Computes the next release tag for an application from existing tags and the
current branch strategy:

| Branch | Tag form | Behavior |
|--------|----------|----------|
| `dev` / `*_dev` | `name_X.Y.Z-devN` | Next dev build; `*_dev` also gets a unique `-<branch>-<timestamp>` postfix |
| `main` | `name_X.Y.Z` | Production release derived from the merged dev or patch line |
| `patch_name_X.Y.Z` | `name_X.Y.Z-patchN` | Patch builds for a specific release line |

```bash
./cicd/scripts/generate-version.sh -n vpnb -b dev
./cicd/scripts/generate-version.sh -n mycs-node-image -v 1 -b main
```

| Option | Description |
|--------|-------------|
| `-n\|--name NAME` | Application name (required); tags are `NAME_…` |
| `-v\|--version N` | Major version (default: `0`) |
| `-b\|--branch NAME` | Branch name (default: `dev`) |
| `-d\|--debug` | Enable `set -x` |
| `-h\|--help` | Show help |

Requires `git`. Prints the next tag name to stdout.

---

## `bump-homebrew-vpn-node-builder.sh`

Updates `Formula/vpn-node-builder.rb` in a local checkout of
`novassist-ai/homebrew-tap` to point at a `vpnb_X.Y.Z` source archive
(`url` + `sha256`, and the `VPNB_IMAGE` pin example in caveats). Does **not**
commit.

Invoked by `.github/workflows/build-vpn-node-builder-prod.yml` after the
`vpnb_X.Y.Z` tag is pushed. Requires repository secret `HOMEBREW_TAP_TOKEN`
(classic or fine-grained PAT with `contents: write` on `novassist-ai/homebrew-tap`).

Dev builds publish `:dev` only; they do not bump the stable formula. Users refresh
containers with `vpnb update` / `vpnb-dev update`.

```bash
./cicd/scripts/bump-homebrew-vpn-node-builder.sh -t vpnb_0.0.1
./cicd/scripts/bump-homebrew-vpn-node-builder.sh -t vpnb_0.0.1 -d /path/to/homebrew-tap
```

| Option | Description |
|--------|-------------|
| `-t\|--tag vpnb_X.Y.Z` | Release tag (required) |
| `-d\|--tap-dir DIR` | Path to tap checkout (default: `./homebrew-tap`) |
| `-r\|--repo OWNER/REPO` | GitHub repo for the archive URL (default: `novassist-ai/mycs-node`) |
| `-h\|--help` | Show help |

---

## `cleanup_releases.sh`

Deletes GitHub releases and git tags older than `-D YYYY-MM-DD`. With
`-p NAME`, only names starting with `NAME_` are considered; otherwise app
prefixes are inferred from tag names (`name_X.Y.Z…`).

Retention matches `generate-version.sh` channels **per app prefix**:

| Channel | Tag form | Kept |
|---------|----------|------|
| prod | `name_X.Y.Z` | N highest semver (default N=1) |
| dev | `name_X.Y.Z-devN` | N highest semver+build (default N=1) |

So a cutoff that covers every matching release/tag still leaves the latest
prod and dev for each app (e.g. `mycs-node-image_0.1.0` and
`mycs-node-image_0.2.0-dev0`). Unversioned tags (`fbr-*`, odd names) keep the
N newest by date.

Fetches `origin` tags first so remote-only tags are included. Uses release
`published_at` / `created_at` for releases and tag creatordate for tags.

```bash
# Dry-run all prefixes: keep latest prod+dev each
./cicd/scripts/cleanup_releases.sh -D 2025-01-01 -d

# Only smart_workflow_*; keep 2 newest prod and 2 newest dev
./cicd/scripts/cleanup_releases.sh -D 2025-01-01 -p smart_workflow -k 2 -y
```

| Option | Description |
|--------|-------------|
| `-D\|--date YYYY-MM-DD` | Delete items older than this date (required) |
| `-p\|--prefix NAME` | Only names starting with `NAME_` |
| `-k\|--keep N` | Keep N newest prod and N newest dev per prefix (default: `1`) |
| `-r\|--releases-only` | Delete only GitHub releases (and their tags) |
| `-t\|--tags-only` | Delete only tags (skip release listing) |
| `-y\|--yes` | Skip confirmation prompt |
| `-d\|--dry-run` | Print what would be deleted |
| `-h\|--help` | Show help |

Requires `gh` (logged in) or `GITHUB_TOKEN`.

---

## `cleanup_workflow_logs.sh`

Deletes GitHub Actions workflow run **logs** older than `-D YYYY-MM-DD` for the
current repo (run records remain). Only completed runs are considered. With
`--delete-runs`, deletes the entire run (and its logs) instead.

Repository is taken from `git remote origin`.

```bash
./cicd/scripts/cleanup_workflow_logs.sh -D 2025-01-01 -d
./cicd/scripts/cleanup_workflow_logs.sh -D 2025-01-01 --delete-runs -y
```

| Option | Description |
|--------|-------------|
| `-D\|--date YYYY-MM-DD` | Delete logs for runs created before this date (required) |
| `--delete-runs` | Delete the whole run instead of logs only |
| `-y\|--yes` | Skip confirmation prompt |
| `-d\|--dry-run` | Print what would be deleted |
| `-h\|--help` | Show help |

Requires `gh` (logged in) or `GITHUB_TOKEN` with repo scope (Actions write for
fine-grained PATs).
