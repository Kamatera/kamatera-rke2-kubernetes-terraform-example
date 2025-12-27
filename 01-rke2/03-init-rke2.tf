resource "random_integer" "servers_ssh_port" {
  min = 52000
  max = 65535
}

locals {
  servers_ssh_port = random_integer.servers_ssh_port.result
  init_rke2_server_script = <<-EOT
      TMPFILE=$(mktemp) &&\
      trap 'rm -f "$TMPFILE"' EXIT &&\
      cat > "$TMPFILE" <<'EOF'
      Host *
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        BatchMode yes
        ConnectTimeout 3
      EOF
      SSHSERVER="root@__PRIVATE_IP__" &&\
      SSHCMD_INITIAL="ssh -F $TMPFILE -J root@${local.bastion_public_ip}:${local.bastion_public_port}" &&\
      SSHCMD="$SSHCMD_INITIAL -p ${local.servers_ssh_port}" &&\
      OK=false &&\
      for i in $(seq 1 60); do
        if $SSHCMD_INITIAL $SSHSERVER true; then
          OK=true
          break
        elif $SSHCMD $SSHSERVER true; then
          SSHCMD_INITIAL="$SSHCMD"
          OK=true
          break
        else
          echo "Waiting for SSH to become available (attempt #$i)..."
          sleep 1
        fi
      done
      if [ "$OK" == "true" ]; then
        echo "${filebase64("${path.module}/../server_startup_script.sh")}" | base64 --decode | \
          $SSHCMD_INITIAL $SSHSERVER "cat >/root/server_startup_script.sh" &&\
        $SSHCMD_INITIAL $SSHSERVER "
          NODE_NAME=__NAME__ CLUSTER_TOKEN=$(cat "${abspath("${path.module}/../.cluster_token")}") bash /root/server_startup_script.sh rke2 __RKE2_ARGS__
        " &&\
        ssh -F $TMPFILE \
          root@${local.bastion_public_ip} -p ${local.bastion_public_port} \
            "ssh-keyscan -p ${local.servers_ssh_port} __PRIVATE_IP__" > "${path.module}/ssh_known_hosts.__NAME__"
      else
        echo "Error: SSH is not available on server __NAME__ after multiple attempts."
        exit 1
      fi
  EOT
  first_controlplane_name = [
    for name, server in var.servers : name
    if server.role == "rke2" && try(tobool(server.role_config.is_first_controlplane), false) == true
  ][0]
  first_controlplane_rke2_config = <<-EOT
    node-name: ${local.first_controlplane_name}
    node-ip: $PRIVATE_IP
    node-external-ip: $PUBLIC_IP
    advertise-address: $PRIVATE_IP
    tls-san:
      - 0.0.0.0
      - $PRIVATE_IP
      - $PUBLIC_IP
    etcd-snapshot-retention: 14  # snapshot every 12 hours, total of 1 week
  EOT
  first_controlplane_ssh_command = replace(replace(replace(local.init_rke2_server_script,
    "__PRIVATE_IP__", kamatera_server.servers[local.first_controlplane_name].private_ips[0]),
    "__NAME__", local.first_controlplane_name),
    "__RKE2_ARGS__", "${local.private_ip_prefix} ${local.servers_ssh_port} server ${var.rke2_version} ${base64encode(local.first_controlplane_rke2_config)}")
  secondary_controlplanes_rke2_config = <<-EOT
      token: $CLUSTER_TOKEN
      server: https://${kamatera_server.servers[local.first_controlplane_name].private_ips[0]}:9345
      node-name: $NODE_NAME
      node-ip: $PRIVATE_IP
      node-external-ip: $PUBLIC_IP
      advertise-address: $PRIVATE_IP
      tls-san:
        - 0.0.0.0
        - $PRIVATE_IP
        - $PUBLIC_IP
      etcd-snapshot-retention: 14  # snapshot every 12 hours, total of 1 week
  EOT
  nodes_rke2_config = <<-EOT
      node-name: $NODE_NAME
      node-ip: $PRIVATE_IP
      node-external-ip: $PUBLIC_IP
      token: $CLUSTER_TOKEN
      server: https://${kamatera_server.servers[local.first_controlplane_name].private_ips[0]}:9345
  EOT
}

resource "terraform_data" "init_rke2_firstcontrolplane" {
  depends_on = [terraform_data.init_bastion]
  triggers_replace = {
    command = <<-EOT
      if [ ! -f "${abspath("${path.module}/../.cluster_token")}" ]; then
        touch "${abspath("${path.module}/../.cluster_token")}"
      fi
      ${local.first_controlplane_ssh_command}
      $SSHCMD $SSHSERVER "cat /var/lib/rancher/rke2/server/node-token" > "${abspath("${path.module}/../.cluster_token")}"
    EOT
  }
  provisioner "local-exec" {
    command = self.triggers_replace.command
    interpreter = ["bash", "-c"]
  }
}

resource "terraform_data" "init_rke2" {
  depends_on = [terraform_data.init_rke2_firstcontrolplane]
  for_each = {
    for name, server in var.servers :
    name => replace(replace(replace(local.init_rke2_server_script,
        "__PRIVATE_IP__", kamatera_server.servers[name].private_ips[0]),
        "__NAME__", name),
        "__RKE2_ARGS__", join(" ", [
          local.private_ip_prefix,
          local.servers_ssh_port,
          server.role_config.rke2_type,
          var.rke2_version,
          base64encode(server.role_config.rke2_type == "server" ? local.secondary_controlplanes_rke2_config : local.nodes_rke2_config)
        ]))
    if server.role == "rke2" && name != local.first_controlplane_name
  }
  triggers_replace = {
    command = each.value
  }
  provisioner "local-exec" {
    command = self.triggers_replace.command
    interpreter = ["bash", "-c"]
  }
}
