resource "random_integer" "bastion_ssh_port" {
  min = 52000
  max = 65535
}

locals {
  bastion_server_names = [for name, server in var.servers : name if server.role == "bastion"]
  bastion_server_name = length(local.bastion_server_names) > 0 ? local.bastion_server_names[0] : ""
  bastion_public_ip = local.bastion_server_name != "" ? kamatera_server.servers[local.bastion_server_name].public_ips[0] : ""
  bastion_public_port = random_integer.bastion_ssh_port.result
}

resource "terraform_data" "init_bastion" {
  count = local.bastion_server_name != "" ? 1 : 0
  depends_on = [kamatera_server.servers]
  triggers_replace = {
    command = <<-EOT
      SSHCMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=3" &&\
      SSHSERVER="root@${local.bastion_public_ip}" &&\
      OK=false &&\
      for i in $(seq 1 60); do
        if $SSHCMD $SSHSERVER true; then
          OK=true
          break
        elif $SSHCMD -p ${local.bastion_public_port} $SSHSERVER true; then
          SSHCMD="$SSHCMD -p ${local.bastion_public_port}"
          OK=true
          break
        else
          echo "Waiting for SSH to become available on bastion (attempt #$i)..."
          sleep 1
        fi
      done
      if [ "$OK" == "true" ]; then
        echo "${filebase64("${path.module}/../server_startup_script.sh")}" | base64 --decode | \
          $SSHCMD $SSHSERVER "cat >/root/server_startup_script.sh" &&\
        $SSHCMD $SSHSERVER "bash /root/server_startup_script.sh bastion ${local.bastion_public_port}" &&\
        ssh-keyscan -p ${local.bastion_public_port} ${local.bastion_public_ip} > "${path.module}/ssh_known_hosts.bastion"
      else
        echo "Error: SSH is not available on bastion after multiple attempts."
        exit 1
      fi
    EOT
  }
  provisioner "local-exec" {
    command = self.triggers_replace.command
    interpreter = ["bash", "-c"]
  }
}
