"""Terraform lifecycle helpers used by vpn-node-builder commands.

## Console output filters

Streamed Terraform commands (`plan`, `apply`, `destroy`) can tee full output to
a log file while applying :mod:`vpn_node_builder.terraform.filters` only to the
console copy.

| Filter | Purpose |
|--------|---------|
| `DropPlanOutNoteFilter` | Hide the speculative-plan “didn't use -out” reminder |
| `drop_prefix(...)` | Drop lines by prefix |
| `compose_filters(...)` | Chain filters for plan/apply/destroy |

Add new filters in `filters.py` and pass them via `compose_filters(...)` to
`run_terraform_tee` from `lifecycle.py`. Log files always keep the unfiltered
stream.
"""
