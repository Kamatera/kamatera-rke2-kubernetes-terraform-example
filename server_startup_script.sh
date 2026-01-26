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

SSS_LOG_FILE_DEFAULT="${ROOT_PATH}/root/server_startup_script.log"
SSS_LOG_FILE="${SSS_LOG_FILE:-${SSS_LOG_FILE_DEFAULT}}"
export SSS_LOG_FILE

function sss_setup_logging {
  mkdir -p "$(dirname "${SSS_LOG_FILE}")" 2>/dev/null || true
  if touch "${SSS_LOG_FILE}" 2>/dev/null; then
    exec > >(tee -a "${SSS_LOG_FILE}") 2>&1
  else
    echo "WARNING: Unable to write log file: ${SSS_LOG_FILE}" >&2
  fi
}

function sss_json_escape {
  local str="${1}"
  str=${str//\\/\\\\}
  str=${str//\"/\\\"}
  str=${str//$'\n'/\\n}
  str=${str//$'\r'/\\r}
  str=${str//$'\t'/\\t}
  printf '%s' "${str}"
}

function sss_slack_notify_failure {
  local exit_code="${1}"
  local webhook_url="${SSS_SLACK_WEBHOOK_URL:-}"
  if [ -z "${webhook_url}" ]; then
    return 0
  fi

  local host
  host="$(hostname 2>/dev/null || echo "unknown")"

  local tail_lines="${SSS_SLACK_TAIL_LINES:-80}"
  local max_chars="${SSS_SLACK_MAX_CHARS:-3500}"
  local log_tail=""
  if [ -n "${SSS_LOG_FILE:-}" ] && [ -f "${SSS_LOG_FILE}" ]; then
    log_tail="$(tail -n "${tail_lines}" "${SSS_LOG_FILE}" 2>/dev/null || true)"
  fi
  if [ -z "${log_tail}" ]; then
    log_tail="(log tail unavailable)"
  fi
  if [ "${#log_tail}" -gt "${max_chars}" ]; then
    log_tail="(truncated to last ${max_chars} chars)
${log_tail: -${max_chars}}"
  fi

  local role="${ROLE:-unknown}"
  local attempt="${SSS_ATTEMPT:-?}"
  local retries="${SSS_RETRIES:-?}"
  local duration_seconds="${SECONDS:-0}"

  local text
  text="$(cat <<EOF
server_startup_script.sh failed
host: ${host}
role: ${role}
attempt: ${attempt}/${retries}
exit: ${exit_code}
duration: ${duration_seconds}s
log: ${SSS_LOG_FILE:-?}

last ${tail_lines} lines:
\`\`\`
${log_tail}
\`\`\`
EOF
)"

  local payload
  payload="{\"text\":\"$(sss_json_escape "${text}")\"}"

  curl -sS -X POST \
    --connect-timeout "${SSS_SLACK_CONNECT_TIMEOUT:-5}" \
    --max-time "${SSS_SLACK_MAX_TIME:-10}" \
    -H 'Content-type: application/json' \
    --data "${payload}" \
    "${webhook_url}" >/dev/null 2>&1 || echo "WARNING: Slack notification failed" >&2
}

function sss_on_exit {
  local exit_code=$?
  if [ "${exit_code}" -ne 0 ]; then
    sss_slack_notify_failure "${exit_code}" || true
    echo "ERROR: server_startup_script.sh failed (exit=${exit_code})" >&2
    if [ -n "${SSS_LOG_FILE:-}" ]; then
      echo "ERROR: Log file: ${SSS_LOG_FILE}" >&2
    fi
  fi
}

sss_setup_logging
SECONDS=0
echo "=== $(date -Is) server_startup_script.sh start role=${ROLE:-unknown} dry_run=${DRY_RUN:-false} ==="
trap sss_on_exit EXIT

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
      systemctl daemon-reload || return 1
      systemctl restart ssh.socket || return 1
      systemctl restart ssh.service || return 1
    fi
}

function init_bastion {
    local bastion_public_port="${1}"
    init_ssh "0.0.0.0" "${bastion_public_port}" || return 1
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
      sysctl --system || return 1
    fi
    rm -f "${ROOT_PATH}/etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf"
    if dry_run; then
      echo "Dry run: would reload and restart systemd-networkd-wait-online.service"
    else
      systemctl daemon-reload || return 1
      if ! systemctl restart systemd-networkd-wait-online.service; then
        echo "WARNING: Failed to restart systemd-networkd-wait-online.service"
      fi
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

function verify_rke2 {
  echo "Verifying RKE2 installation"
  export PATH="/var/lib/rancher/rke2/bin/:$PATH"
  local calico_kubeconfig=/etc/cni/net.d/calico-kubeconfig
  for i in {1..120}; do
    if [ -f "${calico_kubeconfig}" ]; then
      break
    else
      echo "Waiting for Calico kubeconfig to be created..."
      sleep 1
    fi
  done
  if ! [ -f "${calico_kubeconfig}" ]; then
    echo "ERROR! Calico kubeconfig file not found after 2 minutes."
    return 1
  fi
  sleep 5
  if cat /etc/cni/net.d/calico-kubeconfig | grep '\[10.43.0.1\]' && ! kubectl --kubeconfig=$calico_kubeconfig version; then
    sed -i 's#\[10\.43\.0\.1\]#10.43.0.1#g' $calico_kubeconfig
  fi
  if ! kubectl --kubeconfig=$calico_kubeconfig version; then
    echo "ERROR! Unable to connect to RKE2 cluster using Calico kubeconfig."
    return 1
  fi
  echo "RKE2 installation verified successfully"
}

function init_rke2 {
    local private_ip_prefix="${1}"
    local ssh_port="${2}"
    local rke2_type="${3}"
    local rke2_version="${4}"
    local rke2_config_b64="${5}"
    local with_bastion="${6}"
    local private_ip="$(find_ip_by_prefix "${private_ip_prefix}")"
    local public_ip="$(find_public_ip)"
    if [ -z "${private_ip}" ]; then
      echo "ERROR! Could not find private IP with prefix: ${private_ip_prefix}"
      return 1
    fi
    if [ -z "${public_ip}" ]; then
      echo "ERROR! Could not determine public IP"
      return 1
    fi
    echo "Private IP: ${private_ip}"
    echo "Public IP: ${public_ip}"
    if [ "${with_bastion}" == "yes" ]; then
      local ssh_ip="${private_ip}"
    else
      local ssh_ip="0.0.0.0"
    fi
    init_ssh "${ssh_ip}" "${ssh_port}" || return 1
    set_rke2_node_settings || return 1
    echo "Installing RKE2 type=${rke2_type} version=${rke2_version}"
    mkdir -p "${ROOT_PATH}/etc/rancher/rke2"
    export PRIVATE_IP="${private_ip}"
    export PUBLIC_IP="${public_ip}"
    echo "${rke2_config_b64}" | base64 -d | envsubst > "${ROOT_PATH}/etc/rancher/rke2/config.yaml"
    export INSTALL_RKE2_TYPE="${rke2_type}"
    if [[ "$rke2_version" == *+* ]]; then
      export INSTALL_RKE2_VERSION="${rke2_version}"
    else
      export INSTALL_RKE2_CHANNEL="${rke2_version}"
    fi
    if dry_run; then
      echo "Dry run: would install RKE2"
    else
      curl -sfL https://get.rke2.io > rke2_install.sh || return 1
      chmod +x rke2_install.sh
      ./rke2_install.sh || return 1
      if systemctl is-active --quiet "rke2-${rke2_type}.service"; then
        systemctl restart "rke2-${rke2_type}.service" || return 1
      else
        systemctl enable "rke2-${rke2_type}.service" || return 1
        systemctl start "rke2-${rke2_type}.service" || return 1
      fi
      verify_rke2 || return 1
    fi
}

init_func=""
if [ "${ROLE}" == "bastion" ]; then
  init_func="init_bastion"
elif [ "${ROLE}" == "rke2" ]; then
  init_func="init_rke2"
fi
if [ "${init_func}" == "" ]; then
  echo "ERROR! Unknown role: ${ROLE}"
  exit 1
fi

initialized=false
retries=${SSS_RETRIES:-5}
export SSS_RETRIES="${retries}"
for ((i=1; i<=retries; i++)); do
  export SSS_ATTEMPT="${i}"
  if $init_func "${@:2}"; then
    initialized=true
    break
  else
    echo "Initialization attempt ${i} failed, retrying in ${SSS_RETRY_TTL:-30} seconds"
    sss_slack_notify_failure "" || true
    sleep ${SSS_RETRY_TTL:-30}
  fi
done

if [ "${initialized}" == "false" ]; then
  echo "ERROR! Server role initialization failed after multiple attempts"
  exit 1
fi

echo "Server role initialization completed successfully"
exit 0
