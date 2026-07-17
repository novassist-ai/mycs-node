# Terraform helpers

Lifecycle helpers used by vpn-node-builder commands.

## Deployment name and state storage

Buckets / storage accounts are region-bound, so state storage is scoped per
`(cloud, region)` and named from the **workspace folder** (`<folder>` = the
working directory name, lowercased) plus the region. Node types deployed to the
same region share one bucket via the state key.

| Item | Derivation |
|------|------------|
| `TF_VAR_name` (deployment name) | `<folder>-<cloud>-<region>` (region omitted for region-less clouds) |
| s3 / gcs bucket | `vpnb-<folder>-<region>` |
| azurerm storage account | `vpnb<folder><region>` (lowercase alphanumeric, ≤24 chars) |
| azurerm container | `vpnb-<folder>` (region lives in the account) |
| state key / prefix | `<node_type>` |

`TF_VAR_name` is derived in `set_cloud_region()` and is **not** set in
`build-vars.sh`; any stale value there is overridden. Bucket / account and state
key derive from the folder + region + node type independently of `TF_VAR_name`.

## Remote backend cleanup

`delete_backend_resources()` (used by `vpnb destroy-all`) removes the
`(cloud, region)` storage created by `ensure_backend_resources()`:

| Backend | Deleted |
|---------|---------|
| `s3` / `gcs` | Bucket `vpnb-<folder>-<region>` (force) |
| `azurerm` | Storage account `vpnb<folder><region>` (RG `default` kept) |

`vpnb destroy-all` first destroys every deployed node in the workspace, then, for
each configured cloud (credentials present in `cloud-creds.sh`), deletes the
state bucket of every region that had a deployment (only if it exists).

## Console output filters

Streamed Terraform commands (`plan`, `apply`, `destroy`) can tee full output to
a log file while applying `vpn_node_builder.terraform.filters` only to the
console copy.

| Filter | Purpose |
|--------|---------|
| `DropPlanOutNoteFilter` | Hide the speculative-plan “didn't use -out” reminder |
| `drop_prefix(...)` | Drop lines by prefix |
| `compose_filters(...)` | Chain filters for plan/apply/destroy |

Add new filters in `filters.py` and pass them via `compose_filters(...)` to
`run_terraform_tee` from `lifecycle.py`. Log files always keep the unfiltered
stream.
