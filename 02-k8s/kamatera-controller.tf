resource "terraform_data" "apply_kamatera_controller_rbac" {
  triggers_replace = {
    command = <<-EOT
      set -euo pipefail
      export KUBECONFIG="${path.module}/../.kubeconfig"
      curl -s "${var.kamatera_controller_rbac_url != "" ? var.kamatera_controller_rbac_url : "https://raw.githubusercontent.com/Kamatera/kamatera-rke2-controller/refs/heads/main/deploy/rbac.yaml"}" \
        | kubectl apply -f -
    EOT
  }
  provisioner "local-exec" {
    command = self.triggers_replace.command
    interpreter = ["bash", "-c"]
  }
}

resource "kubernetes_secret_v1" "kamatera_controller" {
  metadata {
    name = "kamatera-rke2-controller"
    namespace = "kube-system"
  }
  data = {
    KAMATERA_API_CLIENT_ID = var.cluster_autoscaler_kamatera_api_client_id
    KAMATERA_API_SECRET    = var.cluster_autoscaler_kamatera_api_secret
  }
}

resource "kubernetes_deployment_v1" "kamatera_controller" {
  metadata {
    name = "kamatera-rke2-controller"
    namespace = "kube-system"
    labels = {
      app = "kamatera-rke2-controller"
    }
  }
  spec {
    replicas = var.kamatera_controller_replicas
    selector {
      match_labels = {
        app = "kamatera-rke2-controller"
      }
    }
    template {
      metadata {
        labels = {
          app = "kamatera-rke2-controller"
        }
      }
      spec {
        service_account_name = "kamatera-rke2-controller"
        container {
          name = "controller"
          image = var.kamatera_controller_image == "" ? "ghcr.io/kamatera/kamatera-rke2-controller:latest" : var.kamatera_controller_image
          resources {
            requests = {
              cpu = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu = "50m"
              memory = "64Mi"
            }
          }
          args = var.kamatera_controller_args
          env {
            name = "KAMATERA_API_CLIENT_ID"
            value_from {
              secret_key_ref {
                name = "kamatera-rke2-controller"
                key  = "KAMATERA_API_CLIENT_ID"
              }
            }
          }
          env {
            name = "KAMATERA_API_SECRET"
            value_from {
              secret_key_ref {
                name = "kamatera-rke2-controller"
                key  = "KAMATERA_API_SECRET"
              }
            }
          }
        }
        toleration {
          key = "CriticalAddonsOnly"
          operator = "Exists"
          effect = "NoExecute"
        }
        node_selector = {
          "node-role.kubernetes.io/control-plane": "true"
        }
      }
    }
  }
}
