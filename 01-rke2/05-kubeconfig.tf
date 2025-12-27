resource "terraform_data" "kubeconfig" {
  depends_on = [local_file.ssh_config, terraform_data.ssh_known_hosts]
  triggers_replace = {
    command = <<-EOT
      set -euo pipefail
      FILENAME="${path.module}/../.kubeconfig"
      ssh -F ${abspath("${path.module}/../ssh_config")} ${var.name_prefix}-${local.first_controlplane_name} \
        "cat /etc/rancher/rke2/rke2.yaml" > "$FILENAME"
      sed -i 's|https://127.0.0.1:6443|https://${kamatera_server.servers[local.first_controlplane_name].public_ips[0]}:6443|' "$FILENAME"
    EOT
  }
  provisioner "local-exec" {
    command = self.triggers_replace.command
    interpreter = ["bash", "-c"]
  }
}
