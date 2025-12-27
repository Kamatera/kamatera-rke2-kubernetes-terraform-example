#!/bin/bash

set -euo pipefail

ROLE="${1}"

if [ "${DRY_RUN:-false}" == "true" ]; then
  echo "WARNING: Dry run mode enabled."
  echo "All changes will be simulated."
  echo "File changes will be done under ./.dry_run/"
  function dry_run {
    return 0
  }
  export ROOT_PATH=".dry_run"
else
  function dry_run {
    return 1
  }
  export ROOT_PATH=""
fi

function find_ip_by_prefix {
  local prefix="${1}"
  for ip in $(hostname -I); do
    if [[ "${ip}" == ${prefix}* ]]; then
      echo "${ip}"
      break
    fi
  done
}

function find_public_ip {
  local public_ip
  curl -s http://checkip.amazonaws.com
}

function init_ssh {
    local ip="${1}"
    local port="${2}"
    echo "Initializing ssh server on ${ip}:${port}"
    CLOUD_INIT_CONF_PATH="${ROOT_PATH}/etc/ssh/sshd_config.d/50-cloud-init.conf"
    if [ -f "${CLOUD_INIT_CONF_PATH}" ]; then
      sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' "${CLOUD_INIT_CONF_PATH}"
    fi
    SSH_SOCKET_D_PATH="${ROOT_PATH}/etc/systemd/system/ssh.socket.d"
    mkdir -p "${SSH_SOCKET_D_PATH}"
    cat >"${SSH_SOCKET_D_PATH}/override.conf" <<EOT
[Socket]
ListenStream=
ListenStream=${ip}:${port}
EOT
    if dry_run; then
      echo "Dry run: would reload and restart ssh.socket and ssh.service"
    else
      systemctl daemon-reload
      systemctl restart ssh.socket
      systemctl restart ssh.service
    fi
}

function init_bastion {
    local bastion_public_port="${1}"
    init_ssh "0.0.0.0" "${bastion_public_port}"
}

function set_rke2_node_settings {
    echo "Setting RKE2 node settings"
    mkdir -p "${ROOT_PATH}/etc/sysctl.d"
    cat >"${ROOT_PATH}/etc/sysctl.d/99-cwm.conf" <<'EOF'
vm.max_map_count = 262144
net.ipv4.tcp_retries2 = 8
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches   = 2097152
fs.inotify.max_queued_events  = 65536
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192
EOF
    if dry_run; then
      echo "Dry run: would apply sysctl settings"
    else
      sysctl --system
    fi
    rm -f "${ROOT_PATH}/etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf"
    if dry_run; then
      echo "Dry run: would reload and restart systemd-networkd-wait-online.service"
    else
      systemctl daemon-reload
      systemctl restart systemd-networkd-wait-online.service
    fi
    mkdir -p "${ROOT_PATH}/root/.ssh"
    if ! [ -e "${ROOT_PATH}/root/.ssh/id_rsa" ]; then ssh-keygen -t rsa -b 4096 -N '' -f "${ROOT_PATH}/root/.ssh/id_rsa"; fi
    mkdir -p "${ROOT_PATH}/etc/profile.d"
    cat >"${ROOT_PATH}/etc/profile.d/00-cwm.sh" <<'EOF'
export PATH="/var/lib/rancher/rke2/bin/:$PATH"
export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml
export CONTAINERD_ADDRESS=/run/k3s/containerd/containerd.sock
export CONTAINERD_NAMESPACE=k8s.io
export KUBECONFIG="/etc/rancher/rke2/rke2.yaml"
EOF
}

function init_rke2 {
    local private_ip_prefix="${1}"
    local ssh_port="${2}"
    local rke2_type="${3}"
    local rke2_version="${4}"
    local rke2_config_b64="${5}"
    local private_ip="$(find_ip_by_prefix "${private_ip_prefix}")"
    local public_ip="$(find_public_ip)"
    if [ -z "${private_ip}" ]; then
      echo "ERROR! Could not find private IP with prefix: ${private_ip_prefix}"
      exit 1
    fi
    if [ -z "${public_ip}" ]; then
      echo "ERROR! Could not determine public IP"
      exit 1
    fi
    echo "Private IP: ${private_ip}"
    echo "Public IP: ${public_ip}"
    init_ssh "${private_ip}" "${ssh_port}"
    set_rke2_node_settings
    echo "Installing RKE2 type=${rke2_type} version=${rke2_version}"
    mkdir -p "${ROOT_PATH}/etc/rancher/rke2"
    export PRIVATE_IP="${private_ip}"
    export PUBLIC_IP="${public_ip}"
    echo "${rke2_config_b64}" | base64 -d | envsubst > "${ROOT_PATH}/etc/rancher/rke2/config.yaml"
    if dry_run; then
      echo "Dry run: would install RKE2"
    else
      curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="${rke2_type}" INSTALL_RKE2_VERSION="${rke2_version}" sh -
      if systemctl is-active --quiet "rke2-${rke2_type}.service"; then
        systemctl restart "rke2-${rke2_type}.service"
      else
        systemctl enable "rke2-${rke2_type}.service"
        systemctl start "rke2-${rke2_type}.service"
      fi
    fi
}

if [ "${ROLE}" == "bastion" ]; then
  init_bastion ${@:2}
elif [ "${ROLE}" == "rke2" ]; then
  init_rke2 ${@:2}
else
  echo "ERROR! Unknown role: ${ROLE}"
  exit 1
fi

echo "Server role initialization completed successfully"
exit 0
