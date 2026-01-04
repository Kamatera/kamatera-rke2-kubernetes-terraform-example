// examples of customizing RKE2 charts
// should modify according to your requirements

# resource "kubernetes_manifest" "rke2-ingress-nginx-helm-chart-config" {
#   field_manager {
#     force_conflicts = true
#   }
#   manifest = {
#     apiVersion = "helm.cattle.io/v1"
#     kind       = "HelmChartConfig"
#     metadata = {
#       name      = "rke2-ingress-nginx"
#       namespace = "kube-system"
#     }
#     spec = {
#       valuesContent = <<-EOT
#         controller:
#           kind: Deployment
#           replicaCount: 2
#           affinity:
#             podAntiAffinity:
#               requiredDuringSchedulingIgnoredDuringExecution:
#                 - labelSelector:
#                     matchExpressions:
#                       - key: app.kubernetes.io/name
#                         operator: In
#                         values:
#                           - ingress-nginx
#                   topologyKey: "kubernetes.io/hostname"
#           nodeSelector:
#             "role": "nginx"
#           admissionWebhooks:
#             patch:
#               nodeSelector:
#                 "role": "nginx"
#         defaultBackend:
#           nodeSelector:
#             "role": "nginx"
#       EOT
#     }
#   }
# }

# resource "kubernetes_manifest" "rke2-metrics-server-helm-chart-config" {
#   field_manager {
#     force_conflicts = true
#   }
#   manifest = {
#     apiVersion = "helm.cattle.io/v1"
#     kind       = "HelmChartConfig"
#     metadata = {
#       name      = "rke2-metrics-server"
#       namespace = "kube-system"
#     }
#     spec = {
#       valuesContent = <<-EOT
#         nodeSelector:
#           "role": "general"
#       EOT
#     }
#   }
# }

# resource "kubernetes_manifest" "rke2-snapshot-controller-helm-chart-config" {
#   field_manager {
#     force_conflicts = true
#   }
#   manifest = {
#     apiVersion = "helm.cattle.io/v1"
#     kind       = "HelmChartConfig"
#     metadata = {
#       name      = "rke2-snapshot-controller"
#       namespace = "kube-system"
#     }
#     spec = {
#       valuesContent = <<-EOT
#         controller:
#           nodeSelector:
#             "role": "general"
#       EOT
#     }
#   }
# }
