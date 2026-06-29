locals {
  dns_name_components = split(".", var.vpc_dns_zone)
  parent_dns_name = join(".", slice(
    local.dns_name_components,
    1,
    length(local.dns_name_components)
  ))

  parent_dns_zone_name = (
    length(var.parent_dns_zone_name) > 0
    ? trimsuffix(var.parent_dns_zone_name, ".")
    : local.parent_dns_name
  )

  google_parent_managed_zone_name = (
    length(var.google_parent_managed_zone_name) > 0
    ? var.google_parent_managed_zone_name
    : replace(local.parent_dns_zone_name, ".", "-")
  )
}
