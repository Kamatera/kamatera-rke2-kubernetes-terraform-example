// uncomment to block scheduling non-critical workloads on controlplane nodes

# resource "kubernetes_node_taint" "controlplane" {
#   field_manager = "Terraform_taint_controlplane"
#   for_each = toset(var.controlplane_node_names)
#   metadata {
#     name = each.value
#   }
#   taint {
#     key    = "CriticalAddonsOnly"
#     value  = "true"
#     effect = "NoExecute"
#   }
# }
