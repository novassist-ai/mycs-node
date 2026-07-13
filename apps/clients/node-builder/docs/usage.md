# Usage

How to operate `nb` day to day. For install paths see
[Installation](installation.md); for architecture see [Design](design.md).

## Typical workflow

1. Create an empty project directory (this becomes your working dir).
2. Run `nb init` and accept the [EULA](https://novassist.ai/legal/).
3. Edit `cloud-creds.sh` and `build-vars.sh` (at least set `TF_VAR_name` and
   credentials for the clouds you use).
4. Optionally run `nb doctor` and `nb show-regions <cloud>`.
5. Deploy with `nb deploy-node <NODE_TYPE> <CLOUD> …`.
6. Manage running nodes with `nb show-nodes`, download VPN config, or destroy.

Public clouds require a region (`-r`). Local targets `vagrant-vbox` and `docker`
do not.

---

## Command summary

| Command | Purpose |
|---------|---------|
| `nb init` | Create `cloud-creds.sh` / `build-vars.sh` stubs |
| `nb show-regions` | List regions for aws / azure / google |
| `nb deploy-node` | Plan or apply a recipe |
| `nb reinit-node` | Re-run Terraform init for an existing deployment |
| `nb destroy-node` | Destroy a deployment |
| `nb show-nodes` | Interactive list + actions |
| `nb download-vpn-config` | Download VPN client files |
| `nb start-tunnel` | Run obfuscation tunnel client |
| `nb doctor` | Soft path / tool diagnostics |

Almost all commands require EULA acceptance (stored under `.workspace/run/`).
Deploy-oriented commands also require tools on `PATH` and the two control files
in the working directory (`nb doctor` reports these without failing hard).

---

## `nb init`

```bash
nb init
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

## `nb show-regions`

```bash
nb show-regions <aws|azure|google>
```

Validates credentials from `cloud-creds.sh`, then lists regions via the provider
CLI.

---

## `nb deploy-node`

```bash
nb deploy-node <NODE_TYPE> <CLOUD> [options]
```

Examples:

```bash
nb deploy-node sandbox aws -r us-east-1
nb deploy-node sandbox vagrant-vbox
nb deploy-node sandbox aws -r us-east-1 -s    # plan only
nb deploy-node sandbox aws -r us-east-1 -u    # upgrade/rebuild bastion
```

| Option | Meaning |
|--------|---------|
| `-r/--region` | Required for aws / azure / google |
| `-c/--clean` | Remove `.terraform*` then init |
| `-i/--init` | Force Terraform init |
| `-u/--upgrade` | Taint bastion resources before apply |
| `-a/--no-idle-shutdown` | Disable idle shutdown action |
| `-s/--show` | `terraform plan` only (no apply) |
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

## `nb reinit-node` / `nb destroy-node`

```bash
nb reinit-node <NODE_TYPE> <CLOUD> [-r REGION]
nb destroy-node <NODE_TYPE> <CLOUD> [-r REGION]
```

`reinit-node` refreshes Terraform init / backend wiring without apply or destroy.
`destroy-node` runs `terraform destroy` and removes `output.json`.

---

## `nb download-vpn-config`

```bash
nb download-vpn-config <NODE_TYPE> <CLOUD> \
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

## `nb start-tunnel`

```bash
nb start-tunnel <NODE_TYPE> <CLOUD> -r <REGION> -t <TUNNEL_TYPE>
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

## `nb show-nodes`

Interactive table of deployments discovered from `.workspace/run/**/output.json`.

Select a node, then an action:

1. Update (deploy with `-u`)
2. Download VPN config (running + openvpn/ipsec only)
3. SSH
4. Stop / start
5. Delete (destroy)

---

## `nb doctor`

Prints resolved repo/cookbook/workspace paths, EULA status, presence of control
files, and whether required tools are on `PATH`. Soft checks only — exits `0`
even when tools are missing so you can use it for diagnosis.
