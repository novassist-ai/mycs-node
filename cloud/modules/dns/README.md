# DNS modules

Provider-specific Terraform modules for delegating a **public** DNS zone and publishing bastion records.

| Module | Provider |
|--------|----------|
| `modules/dns/aws` | AWS Route53 |
| `modules/dns/google` | Google Cloud DNS |
| `modules/dns/azure` | Azure DNS |

Use when compute runs on a platform without a native DNS API (for example OpenStack/OVH) but public DNS should be managed in an existing cloud DNS service. All record targets are supplied as inputs; there is no private/split-horizon DNS.

## Usage

Call the module matching your DNS provider directly, or let the OpenStack bootstrap module select it via `dns_provider`:

```hcl
module "dns" {
  source = "../../modules/dns/aws"

  vpc_name     = "inceptor-uk1"
  vpc_dns_zone = "test-uk1.ovh.appbricks.io"

  bastion_public_ip    = "203.0.113.10"
  bastion_admin_itf_ip = "172.20.65.253"

  bastion_host_name        = "inceptor"
  bastion_allow_public_ssh = true
  smtp_relay_host          = ""
}
```

Configure only the provider you use in the root module. Unused provider modules are not loaded.

## Common inputs

| Name | Description |
|------|-------------|
| `vpc_name` | Tag/name metadata for the delegated zone. |
| `vpc_dns_zone` | FQDN of the child zone (no trailing dot). |
| `bastion_public_ip` | Public A record target (floating IP). |
| `bastion_admin_itf_ip` | Admin interface IP for mail/admin records. |
| `bastion_host_name` | Optional admin host label in the public zone. |
| `bastion_allow_public_ssh` | When true, admin A record is skipped. |
| `smtp_relay_host` | When set, creates mail/MX/TXT records. |
| `parent_dns_zone_name` | Parent zone for NS delegation (defaults from `vpc_dns_zone`). |

## Provider-specific inputs

| Module | Extra inputs |
|--------|--------------|
| `azure` | `azure_resource_group` (required) |
| `google` | `google_parent_managed_zone_name` (optional; defaults from `parent_dns_zone_name`) |

## Outputs

All modules expose: `vpc_dns_public_zone_id`, `vpc_dns_public_zone_name`, `vpc_dns_private_zone_id` (empty), `vpc_dns_private_zone_name` (empty), `bastion_fqdn`.

## OpenStack integration

`modules/bootstrap/openstack/dns.tf` calls `modules/dns/aws` when `attach_dns_zone` is true and `dns_provider = "aws"`. For Google or Azure DNS on OpenStack, call `modules/dns/google` or `modules/dns/azure` from your root module.

## Notes

- Internal `.local` zones remain on PowerDNS inside the bastion.
- Google Cloud DNS parent lookup uses the managed zone **resource name**; override with `google_parent_managed_zone_name` when it differs from the domain (e.g. `gcp-appbricks-cloud`).
