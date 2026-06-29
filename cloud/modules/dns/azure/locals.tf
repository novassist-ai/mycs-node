locals {
  dns_name_components = split(".", var.vpc_dns_zone)
  parent_dns_name = join(".", slice(
    local.dns_name_components,
    1,
    length(local.dns_name_components)
  ))
  vpc_dns_hostname = element(local.dns_name_components, 0)

  parent_dns_zone_name = (
    length(var.parent_dns_zone_name) > 0
    ? trimsuffix(var.parent_dns_zone_name, ".")
    : local.parent_dns_name
  )

  azure_parent_zone_name = local.parent_dns_zone_name
}
