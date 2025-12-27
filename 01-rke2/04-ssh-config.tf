resource "terraform_data" "ssh_known_hosts" {
  depends_on = [terraform_data.init_rke2]
  triggers_replace = {
    server_names = [for name, server in var.servers : name]
    command = <<-EOT
      set -euo pipefail
      SSH_KNOWN_HOSTS_FILE="${abspath("${path.module}/../ssh_known_hosts")}"
      rm -f "$SSH_KNOWN_HOSTS_FILE"
      touch "$SSH_KNOWN_HOSTS_FILE"
      for file in ${abspath("${path.module}/ssh_known_hosts.*")}; do
        if [ -f "$file" ]; then
          cat "$file" >> "$SSH_KNOWN_HOSTS_FILE"
        fi
      done
    EOT
  }
  provisioner "local-exec" {
    command = self.triggers_replace.command
    interpreter = ["bash", "-c"]
  }
}

resource "local_file" "ssh_config" {
  depends_on = [terraform_data.init_rke2]
  filename = "${path.module}/../ssh_config"
  content = join(
    "\n",
    concat(
      [
        <<-EOT
          Host ${var.name_prefix}-bastion
            HostName ${local.bastion_public_ip}
            User root
            Port ${local.bastion_public_port}
            UserKnownHostsFile ${abspath("${path.module}/../ssh_known_hosts")}
        EOT
      ],
      [
        for name, server in var.servers : <<-EOT
          Host ${var.name_prefix}-${name}
            HostName ${kamatera_server.servers[name].private_ips[0]}
            User root
            Port ${local.servers_ssh_port}
            ProxyJump ${var.name_prefix}-bastion
            UserKnownHostsFile ${abspath("${path.module}/../ssh_known_hosts")}
        EOT
        if server.role == "rke2"
      ]
    )
  )
}
