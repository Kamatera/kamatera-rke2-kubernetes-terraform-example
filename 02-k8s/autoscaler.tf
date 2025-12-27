resource "terraform_data" "apply_autoscaler" {
  triggers_replace = {
    autoscaler_yaml_hash = filemd5("${path.module}/autoscaler.yaml")
    command = <<-EOT
      set -euo pipefail
      export KUBECONFIG="${path.module}/../.kubeconfig"
      kubectl apply -f "${path.module}/autoscaler.yaml"
    EOT
  }
  provisioner "local-exec" {
    command = self.triggers_replace.command
    interpreter = ["bash", "-c"]
  }
}

locals {
  autoscaler_script = <<-EOT
    echo "${filebase64("${path.module}/../server_startup_script.sh")}" | base64 --decode > /root/server_startup_script.sh
    export CLUSTER_TOKEN=${file("${path.module}/../.cluster_token")}
    export NODE_NAME="$(hostname | cut -d'-' -f2-)"
    bash /root/server_startup_script.sh rke2 "${var.private_ip_prefix}" "${var.servers_ssh_port}" "agent" "${var.rke2_version}" "${base64encode(var.rke2_config)}" | tee /root/server_startup_script.log 2>&1
  EOT

  nodegroup_configs = join("\n\n", [
    for name, ng in var.cluster_autoscaler_nodegroup_configs : <<-EOT
      [nodegroup "${name}"]
      name-prefix=${var.name_prefix}-${name}
      ${ng}
    EOT
  ])
}

resource "kubernetes_secret_v1" "autoscaler" {
  metadata {
    name = "cluster-autoscaler-kamatera"
    namespace = "kube-system"
  }
  data = {
    "cloud-config" = <<-EOT
      [global]
      kamatera-api-client-id=${var.cluster_autoscaler_kamatera_api_client_id}
      kamatera-api-secret=${var.cluster_autoscaler_kamatera_api_secret}
      cluster-name=${var.name_prefix}
      filter-name-prefix=${var.name_prefix}
      default-datacenter=${var.datacenter_id}
      default-image=${var.image_id}
      default-script-base64=${base64encode(local.autoscaler_script)}
      default-network = "name=wan,ip=auto"
      default-network = "name=${var.private_network_name},ip=auto"
      ${var.cluster_autoscaler_global_config}


      ${local.nodegroup_configs}
    EOT
  }
}


resource "kubernetes_deployment_v1" "autoscaler" {
  lifecycle {
    replace_triggered_by = [
      kubernetes_secret_v1.autoscaler.data
    ]
  }
  metadata {
    name = "cluster-autoscaler"
    namespace = "kube-system"
    labels = {
      app = "cluster-autoscaler"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "cluster-autoscaler"
      }
    }
    template {
      metadata {
        labels = {
          app = "cluster-autoscaler"
        }
      }
      spec {
        service_account_name = "cluster-autoscaler"
        container {
          name = "cluster-autoscaler"
          # image = "registry.k8s.io/autoscaling/cluster-autoscaler:v${var.cluster_autoscaler_version}"
          # this image includes a fix to allow setting node template labels, waiting for it to be merged upstream
          image = "ghcr.io/kamatera/kubernetes-autoscaler:v1.32-with-node-template-labels"
          resources {
            requests = {
              cpu = "100m"
              memory = "600Mi"
            }
            limits = {
              cpu = "100m"
              memory = "600Mi"
            }
          }
          command = [
            "./cluster-autoscaler",
            "--cloud-provider=kamatera",
            "--cloud-config=/config/cloud-config",
            "--v=2",
            "--logtostderr=true",
            "--namespace=kube-system"
          ]
          volume_mount {
            name = "cloud-config"
            mount_path = "/config"
            read_only = true
          }
        }
        volume {
          name = "cloud-config"
          secret {
            secret_name = kubernetes_secret_v1.autoscaler.metadata[0].name
          }
        }
        toleration {
          key = "CriticalAddonsOnly"
          operator = "Exists"
          effect = "NoExecute"
        }
      }
    }
  }
}
