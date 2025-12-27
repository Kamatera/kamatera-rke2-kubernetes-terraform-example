# kamatera-rke2-kubernetes-terraform-example

Example terraform configuration for setting up a Kubernetes cluster using RKE2 on Kamatera

## Prerequisites

* [Terraform](https://developer.hashicorp.com/terraform/install)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [Kamatera Console Account](https://console.kamatera.com/)

## Installation / Deployment

The terraform modules are ordered based on the directory name (`01-...`, `02-...`, etc.).
You should run them in order to set up the entire infrastructure.

Each module directory container a `terraform.tfvars.example` file which you should copy to `terraform.tfvars` and edit
with your own values. The example files contain comments to help you understand what values are required. You can
also check the `variables.tf` file for each module to see what variables are available.

Use terraform commands to initialize, plan, and apply the configuration for each module directory.

The modules will create some files locally to store state and configuration information.
Make sure to keep these files safe and private.

## Architecture / Configuration

### Terraform

Terraform modules are idempotent, meaning you can run `terraform apply` multiple times without causing unintended changes.

Make sure to run the modules in correct order.

### Servers

#### SSH

Servers SSH server is configured to listen on a random port and only on the private network interface.

The bastion server is the only server that listens on the public network interface and is used only for SSH access.

The Terraform module will create an `ssh_config` file that can be used to SSH to the permanent servers.

Authentication is done using SSH keys, you need to provide your public key in the `terraform.tfvars` file.

#### Permanent Servers

Permanent servers are created using Kamatera Terraform provider.

The servers are configured in the `01-rke2/terraform.tfvars` file.

The following servers are the minimum required:

* 1 Bastion server
* 1 RKE2 ControlPlane server 

#### Autoscaling Servers

Autoscaling servers are managed by the Kamatera Cluster Autoscaler, see documentation [here](https://github.com/Kamatera/kubernetes-autoscaler/blob/add-support-for-node-template-labels/cluster-autoscaler/cloudprovider/kamatera/README.md)

Configuration for the autoscaler node groups is in `02-k8s/terraform.tfvars` file.

### RKE2

RKE2 is used to manage the Kubernetes cluster.

Refer to the [RKE2 documentation](https://docs.rke2.io/) for more information.

RKE2 configurations are defined in `01-rke2/03-init-rke2.tf` in locals, there are 3 configurations:

* `locals.first_controlplane_rke2_config`
* `locals.secondary_controlplanes_rke2_config`
* `locals.nodes_rke2_config`

You can modify the configurations as needed. The `nodes_rke2_config` configurations is also used by the autoscaler node groups.

Kubeconfig file to access the cluster is created in `.kubeconfig`
