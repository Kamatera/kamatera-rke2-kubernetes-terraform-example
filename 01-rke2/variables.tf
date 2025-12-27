variable "name_prefix" {
  description = "Prefix for naming of resources"
  type        = string
}

variable "servers" {
  description = "Map of servers to create, key is the server name (name_prefix will be prepended). server key 'default' can be used to set default values for all servers."
  type = map(object({
    role = optional(string)  # main role of the server, determines next steps, possible values:
                             # bastion - server used as bastion host for SSH access to other servers
                             # rke2 - used as a node in the RKE2 cluster
    role_config = optional(map(string))  # role specific configuration
    server_name = optional(string)  # Kamatera server name to set, if not set will use "${name_prefix}-${key}"
    # following are Kamatera server parameters, see https://registry.terraform.io/providers/kamatera/kamatera/latest/docs/resources/server
    image_id = optional(string)
    billing_cycle = optional(string)
    cpu_cores = optional(number)
    cpu_type = optional(string)
    daily_backup = optional(bool)
    disk_sizes_gb = optional(list(number))
    managed = optional(bool)
    monthly_traffic_package = optional(number)
    ram_mb = optional(number)
  }))
}

variable "datacenter_id" {
  description = "Kamatera datacenter ID where servers and related resources will be created."
  type        = string
}

variable "server_image_config" {
  description = "Object containing attributes for image datasource to find the relevant image id, see https://registry.terraform.io/providers/Kamatera/kamatera/latest/docs/data-sources/image"
  type = object({
    code = optional(string)
    os = optional(string)
    id = optional(string)
    private_image_name = optional(string)
  })
  default = {
    os = "Ubuntu"
    code = "24.04 64bit"
  }
}

variable "ssh_pubkeys" {
  description = "SSH public keys to be added to all servers for access."
  type        = string
}

variable "private_network_name" {
  description = "Name of the private network to create for the servers, if not specified will use {name_prefix}-private'."
  type        = string
  default = null
}

variable "rke2_version" {
  description = "RKE2 version to install"
  type        = string
  default     = "v1.32.11+rke2r1"
}

variable "kamatera_api_client_id" {
  description = "Kamatera API client ID"
  type        = string
  sensitive = true
}

variable "kamatera_api_secret" {
  description = "Kamatera API secret"
  type        = string
  sensitive = true
}
