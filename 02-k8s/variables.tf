variable "cluster_autoscaler_version" {
  description = "Cluster Autoscaler version to deploy"
  type        = string
  default     = ""
}

variable "cluster_autoscaler_image" {
  description = "Optionally, specify a custom Cluster Autoscaler image"
  type        = string
  default     = ""
}

variable "cluster_autoscaler_rbac_url" {
  description = "Optionally, URL for the Cluster Autoscaler RBAC manifest"
  type        = string
  default     = ""
}

variable "cluster_autoscaler_kamatera_api_client_id" {
  description = "Kamatera API Client ID for Cluster Autoscaler"
  type        = string
  sensitive = true
}

variable "cluster_autoscaler_kamatera_api_secret" {
  description = "Kamatera API Secret for Cluster Autoscaler"
  type        = string
  sensitive = true
}

variable "name_prefix" {
  description = "Prefix for naming resources"
  type        = string
}

variable "image_id" {
  description = "Kamatera Image ID to use for the autoscaler"
  type        = string
}

variable "datacenter_id" {
  description = "Kamatera Datacenter ID for the autoscaler"
  type        = string
}

variable "private_network_name" {
  description = "Name of the private network to attach the autoscaler servers to"
  type        = string
}

variable "cluster_autoscaler_global_config" {
  description = "global configurations for Cluster Autoscaler cloud-config, see https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/kamatera/README.md"
  type        = string
  default     = ""
}

variable "cluster_autoscaler_nodegroup_configs" {
  description = "Map of nodegroup specific configurations for Cluster Autoscaler, key is the nodegroup name, value is the configurations, see https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/kamatera/README.md"
  type        = map(string)
  default     = {}
}

variable "rke2_version" {
  description = "RKE2 version to use for the autoscaler"
  type        = string
}

variable "private_ip_prefix" {
  description = "Private IP prefix for the autoscaler servers"
  type        = string
}

variable "servers_ssh_port" {
  description = "SSH port for the autoscaler servers"
  type        = string
}

variable "rke2_config" {
  description = "RKE2 configuration for the autoscaler servers"
  type        = string
}

variable "controlplane_node_names" {
  description = "List of control plane node names to taint"
  type        = list(string)
}

variable "cluster_autoscaler_nodegroup_rke2_extra_config" {
  description = "Map of extra RKE2 configurations for each nodegroup in Cluster Autoscaler"
  type        = map(string)
  default     = {}
}

variable "cluster_autoscaler_extra_args" {
  description = "Extra arguments to pass to the Cluster Autoscaler container"
  type        = list(string)
  default     = []
}

variable "cluster_autoscaler_replicas" {
  description = "Number of replicas for the Cluster Autoscaler deployment"
  type        = number
  default     = 1
}

variable "with_bastion" {
  description = "Whether a bastion host is used for SSH access"
  type        = bool
  default     = true
}

variable "kamatera_controller_rbac_url" {
  description = "Optionally, URL for the Kamatera Cloud Controller Manager RBAC manifest"
  type        = string
  default     = ""
}

variable "kamatera_controller_replicas" {
  description = "Number of replicas for the Kamatera Controller"
  type        = number
  default     = 1
}

variable "kamatera_controller_image" {
  description = "Optionally, specify a custom Kamatera Controller image"
  type        = string
  default     = ""
}

variable "kamatera_controller_args" {
  description = "Aarguments to pass to the Kamatera Controller"
  type        = list(string)
  default     = [
    "-not-ready-duration=15m"
  ]
}

variable "cluster_autoscaler_slack_webhook_url" {
  description = "Slack webhook URL for Cluster Autoscaler notifications from server startup script"
  type        = string
  default     = ""
}
