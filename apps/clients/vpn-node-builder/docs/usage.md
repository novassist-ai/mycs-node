# Usage

How to operate `vpnb` day to day. For install paths see
[Installation](installation.md); for architecture see [Design](design.md).

## Typical workflow

1. Create an empty project directory (this becomes your working dir).
2. Run `vpnb init` and accept the [EULA](https://novassist.ai/legal/).
3. Edit `cloud-creds.sh` and `build-vars.sh` (at least set `TF_VAR_name` and
   credentials for the clouds you use).
4. Optionally run `vpnb doctor` and `vpnb show-regions <cloud>`.
5. Deploy with `vpnb deploy-node <NODE_TYPE> <CLOUD> …`.
6. Manage running nodes with `vpnb show-nodes`, download VPN config, or destroy.

Public clouds require a region (`-r`). Local targets `vagrant-vbox` and `docker`
do not.

---

## Command summary

| Command | Purpose |
|---------|---------|
| `vpnb init` | Create `cloud-creds.sh` / `build-vars.sh` stubs |
| `vpnb show-regions` | List regions for aws / azure / google |
| `vpnb deploy-node` | Plan or apply a recipe |
| `vpnb reinit-node` | Re-run Terraform init for an existing deployment |
| `vpnb destroy-node` | Destroy a deployment |
| `vpnb show-nodes` | Interactive list + actions |
| `vpnb download-vpn-config` | Download VPN client files |
| `vpnb start-tunnel` | Run obfuscation tunnel client |
| `vpnb doctor` | Soft path / tool diagnostics |

Almost all commands require EULA acceptance (stored under `.workspace/run/`).
Deploy-oriented commands also require tools on `PATH` and the two control files
in the working directory (`vpnb doctor` reports these without failing hard).
`cloud-creds.sh`, `build-vars.sh`, and per-run `input-vars.sh` are **sourced via
bash** (same as the legacy spacenode CLI), so shell expansions in those files
resolve correctly.

---

## `vpnb init`

```bash
vpnb init
```

Creates stubs **only if missing** (never overwrites):

| File | Purpose |
|------|---------|
| `cloud-creds.sh` | `AWS_*`, `GOOGLE_*`, `ARM_*` |
| `build-vars.sh` | `TF_VAR_name`, DNS, cert DN, VPN users, idle timeout |

Also ensures `.workspace/run` and `.workspace/templates` exist. Templates link
to cookbook recipes when the cookbook path is resolvable.

Cert DN defaults use NovAssist branding (`novassist` / `novassist dev`).

`init` does **not** require Terraform or cloud CLIs.

---

## `vpnb show-regions`

```bash
vpnb show-regions <aws|azure|google>
```

Validates credentials from `cloud-creds.sh`, then lists regions via the provider
CLI.

---

## `vpnb deploy-node`

```bash
vpnb deploy-node <NODE_TYPE> <CLOUD> [options]
```

Examples:

```bash
vpnb deploy-node sandbox aws -r us-east-1
vpnb deploy-node sandbox vagrant-vbox
vpnb deploy-node sandbox aws -r us-east-1 -s    # plan only
vpnb deploy-node sandbox aws -r us-east-1 -u    # rebuild bastion VM (keep data volume)
vpnb deploy-node sandbox aws -r us-east-1 -b    # rebuild bastion VM + data volume
vpnb deploy-node            # lists available NODE_TYPE values
vpnb deploy-node sandbox    # lists available CLOUD targets for that type
```

| Option | Meaning |
|--------|---------|
| `-r/--region` | Required for aws / azure / google (lists regions if omitted) |
| `-c/--clean` | Remove `.terraform*` then init |
| `-i/--init` | Force Terraform init |
| `-u/--upgrade` | Taint bastion VM (`@resource_instance_list`) before apply; keeps data store |
| `-b/--rebuild` | Taint bastion VM and data store (`@resource_instance_data_list`) before apply |
| `-a/--no-idle-shutdown` | Disable idle shutdown action |
| `-s/--show` | `terraform plan` only (no apply) |
| `-d/--debug` | Trace external commands (`+ …`) |
| `--dev` | Print dependent-recipe input variables |

**Dependent recipes** use:

```text
<input_node>[@<cloud>]:<cookbook>:<recipe>
```

Outputs from the input node are exported as `TF_VAR_*` into `input-vars.sh`
under the deployment run directory.

State and keys land under
`.workspace/run/<node_type>/<cloud>/[<region>/]` (`output.json`, SSH PEMs).

---

## `vpnb reinit-node` / `vpnb destroy-node`

```bash
vpnb reinit-node <NODE_TYPE> <CLOUD> [-r REGION]
vpnb destroy-node <NODE_TYPE> <CLOUD> [-r REGION]
vpnb destroy-node sandbox aws -r us-east-1 -x   # also delete remote state storage
```

`reinit-node` refreshes Terraform init / backend wiring without apply or destroy.
`destroy-node` runs `terraform destroy` and removes `output.json`.

| Option | Meaning |
|--------|---------|
| `-r/--region` | Required for aws / azure / google |
| `-x/--delete-remote-state` | After destroy, delete s3/gcs state bucket `{TF_VAR_name}-vpn-tfstate-{region}`, or the Azure storage container named `TF_VAR_name` |
| `-d/--debug` | Trace external commands |

**Caution:** the s3/gcs bucket is shared by all node types for the same deployment name and region; `-x` removes the whole bucket.

---

## `vpnb download-vpn-config`

```bash
vpnb download-vpn-config <NODE_TYPE> <CLOUD> \
  -r <REGION> -u <USERNAME> -p <PASSWORD>
```

- Writes client files under `configs/<node_name>/` in the working directory.
- Retries until the node HTTPS endpoint is reachable.
- **WireGuard:** not downloaded here — use the MyCS client API.
- If VPN masking is available (`yes` / `true`), also downloads executable
  `client_tunnel` into the deployment run directory.

On macOS, OpenVPN/IPsec profiles are opened with the system `open` command after
download.

---

## `vpnb start-tunnel`

```bash
vpnb start-tunnel <NODE_TYPE> <CLOUD> -r <REGION> -t <TUNNEL_TYPE>
```

| Argument | Notes |
|----------|--------|
| `NODE_TYPE` | Required (needed to resolve the deployment workspace) |
| `-t/--type` | One of the types below |

Tunnel types:

- `udp_over_tcp`
- `udp_over_icmp`
- `udp_over_udp`
- `udp_over_udp_with_fec`
- `tcp_over_udp_with_fec`

Requires a prior `download-vpn-config` that fetched `client_tunnel`. Starts the
node if it is stopped, waits until running, then executes the tunnel script.

---

## `vpnb show-nodes`

Interactive table of deployments discovered from `.workspace/run/**/output.json`.

Select a node, then an action:

1. Update (deploy with `-u`)
2. Download VPN config (running + openvpn/ipsec only)
3. SSH
4. Stop / start
5. Delete (destroy)

---

## `vpnb doctor`

Prints resolved repo/cookbook/workspace paths, EULA status, presence of control
files, and whether required tools are on `PATH`. Soft checks only — exits `0`
even when tools are missing so you can use it for diagnosis.
