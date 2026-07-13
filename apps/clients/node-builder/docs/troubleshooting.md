# Troubleshooting

Quick fixes for common `nb` issues. For command semantics see [Usage](usage.md).

---

## Development install

### `nb: command not found`

1. Activate the virtualenv (`.venv`).
2. Reinstall editable: `pip install -e ".[dev]"`.
3. Fallback: `python -m node_builder.cli --help`.

### Cookbook / recipes not found

- Prefer working inside the `mycs-node` checkout, **or** set:

  ```bash
  export NB_COOKBOOK_PATH=/path/to/mycs-node/cloud/cookbook
  ```

- Confirm with `nb doctor` (cookbook / recipes / template paths).
- If `.workspace/templates` was created before the cookbook was available, remove
  it and re-run `nb init` or `nb doctor` so links can be created.

### Tests fail to import `node_builder`

```bash
pip install -e ".[dev]"
# or
PYTHONPATH=src pytest
```

---

## EULA

### Prompted every time / cannot proceed

- Acceptance file: `.workspace/run/eula_accepted` (under the working directory).
- You must type exactly `yes` (not `y`).
- Terms: https://novassist.ai/legal/
- Tests/CI only: `NB_SKIP_EULA=1`

---

## Credentials and tools

### Missing `cloud-creds.sh` / `build-vars.sh`

```bash
nb init
```

Then set at least `TF_VAR_name` and the credentials for the clouds you use.
Files must live in the **current working directory** (mounted as `/work` in
Docker for end users).

### Missing `aws` / `az` / `gcloud` / `terraform` / `jq`

- `nb doctor` lists what is missing and install URLs.
- Native development: install tools on the host.
- End-user Docker image (Phase 6): tools are bundled — ensure the launcher is
  used, not a bare host Python without those CLIs.

### Cloud credential errors on deploy

- Variable names match the stubs (`AWS_ACCESS_KEY` / `AWS_SECRET_KEY`, not only
  `AWS_ACCESS_KEY_ID` — `nb` maps them for the AWS CLI).
- Azure needs `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`.
- Google needs `GOOGLE_CREDENTIALS` (key file path) and `GOOGLE_PROJECT`.

---

## Deploy / Terraform

### Region required

Public clouds need `-r/--region`. List options:

```bash
nb show-regions aws
```

### Backend / state bucket failures

- Set `TF_VAR_name` in `build-vars.sh`.
- Credentials must allow creating the state bucket (S3), storage account
  (Azure), or GCS bucket.
- Local targets (`vagrant-vbox`, `docker`) use the `local` backend;
  `deploy-node` sets `TF_VAR_cb_local_state_path` under the run directory.

### Go util symlinks broken (`vagrant-vbox` / approuter docker)

From the repo root:

```bash
./apps/clients/node-builder/scripts/build-utils.sh :dev:clean-all:
```

Confirm `.build/bin` exists and recipe symlinks resolve to it.

### Plan-only check

```bash
nb deploy-node sandbox aws -r us-east-1 -s
```

---

## VPN and tunnels

### WireGuard config not downloaded

Expected — WireGuard is configured via the MyCS client API, not
`download-vpn-config`.

### `download-vpn-config` waits forever

The node HTTPS API may still be starting, or credentials / host / port are
wrong. Check `output.json` for FQDN / public IP / `api_port`, and that the
instance is `running` (`nb show-nodes`).

### `start-tunnel` fails: no `client_tunnel`

Run `nb download-vpn-config …` first for a node that advertises VPN masking
(`cb_vpn_masking_available` = `yes` or `true`).

### `start-tunnel` usage

```bash
nb start-tunnel <NODE_TYPE> <CLOUD> -r <REGION> -t udp_over_tcp
```

Both node type and cloud are required so the deployment directory can be
resolved.

---

## Still stuck?

1. `nb doctor`
2. Confirm working directory and `.workspace/run/…` layout ([Design](design.md))
3. Re-run with a clean plan (`-s`) before apply
