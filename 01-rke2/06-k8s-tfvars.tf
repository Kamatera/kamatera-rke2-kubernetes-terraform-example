resource "local_file" "autoscaler_tfvars" {
  filename = "${path.module}/../02-k8s/autoscaler.auto.tfvars.json"
  content = jsonencode({
    name_prefix = var.name_prefix
    image_id = data.kamatera_image.server.id
    datacenter_id = var.datacenter_id
    private_network_name = kamatera_network.private.full_name
    rke2_version = var.rke2_version
    private_ip_prefix = local.private_ip_prefix
    servers_ssh_port = local.servers_ssh_port
    rke2_config = local.nodes_rke2_config
    with_bastion = local.bastion_public_ip != ""
  })
}

resource "local_file" "taint_tfvars" {
  filename = "${path.module}/../02-k8s/taints.auto.tfvars.json"
  content = jsonencode({
    controlplane_node_names = concat(
      [local.first_controlplane_name],
      [
        for name, server in var.servers : name
        if server.role == "rke2" && try(server.role_config.rke2_type, "") == "server" && name != local.first_controlplane_name
      ]
    )
  })
}
