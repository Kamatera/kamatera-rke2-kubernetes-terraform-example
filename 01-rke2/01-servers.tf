data "kamatera_image" "server" {
  datacenter_id = var.datacenter_id
  code = var.server_image_config.code
  os = var.server_image_config.os
  id = var.server_image_config.id
  private_image_name = var.server_image_config.private_image_name
}

locals {
  private_ip_prefix = "172.16."
  private_ip_suffix = "0.0"
}

resource "kamatera_network" "private" {
  datacenter_id = var.datacenter_id
  name          = coalesce(var.private_network_name, "${var.name_prefix}-private")
  subnet {
    ip = "${local.private_ip_prefix}${local.private_ip_suffix}"
    bit = 23
  }
}

resource "kamatera_server" "servers" {
  for_each = {
    for name, server in var.servers : name => server
    if try(server.role, "") != "" && name != "default"
  }
  datacenter_id = var.datacenter_id
  image_id = coalesce(each.value.image_id, var.servers["default"].image_id, data.kamatera_image.server.id)
  name = coalesce(each.value.server_name, "${var.name_prefix}-${each.key}")
  allow_recreate = true
  billing_cycle = coalesce(each.value.billing_cycle, var.servers["default"].billing_cycle)
  cpu_cores = coalesce(each.value.cpu_cores, var.servers["default"].cpu_cores)
  cpu_type = coalesce(each.value.cpu_type, var.servers["default"].cpu_type)
  daily_backup = try(coalesce(each.value.daily_backup, var.servers["default"].daily_backup), false)
  disk_sizes_gb = coalesce(each.value.disk_sizes_gb, var.servers["default"].disk_sizes_gb)
  managed = try(coalesce(each.value.managed, var.servers["default"].managed), false)
  monthly_traffic_package = try(coalesce(each.value.monthly_traffic_package, var.servers["default"].monthly_traffic_package), null)
  ram_mb = coalesce(each.value.ram_mb, var.servers["default"].ram_mb)
  ssh_pubkey = var.ssh_pubkeys

  network {
    name = "wan"
  }

  network {
    name = kamatera_network.private.full_name
  }

  lifecycle {
    ignore_changes = [ssh_pubkey]
  }
}
