import dataclasses
import os
import secrets
import datetime
import subprocess
import json

from . import config, util


def get_rke2_servers(with_bastion, extra_servers=None):
    servers = {
        "default": {
            "billing_cycle": "hourly",
            "daily_backup": False,
            "managed": False,
            "cpu_type": "B",
            "disk_sizes_gb": [100],
        },
        "controlplane1": {
            "role": "rke2",
            "role_config": {
                "rke2_type": "server",
                "is_first_controlplane": True,
            },
            "cpu_cores": 4,
            "ram_mb": 8192,
        }
    }
    if with_bastion:
        servers["bastion"] = {
            "role": "bastion",
            "cpu_cores": 1,
            "ram_mb": 1024,
            "disk_sizes_gb": [20],
        }
    if extra_servers:
        servers.update(extra_servers)
    return servers


def write_rke2_tfvars(tfdir, name_prefix, rke2_version, datacenter_id, ssh_pubkeys, with_bastion, extra_servers):
    assert not os.path.exists(os.path.join(tfdir, "01-rke2", "ktb.auto.tfvars.json"))
    with open(os.path.join(tfdir, "01-rke2", "ktb.auto.tfvars.json"), "w") as f:
        f.write(json.dumps({
            "kamatera_api_client_id": config.KAMATERA_API_CLIENT_ID,
            "kamatera_api_secret": config.KAMATERA_API_SECRET,
            "datacenter_id": datacenter_id,
            "name_prefix": name_prefix,
            "ssh_pubkeys": ssh_pubkeys,
            "rke2_version": rke2_version,
            "servers": get_rke2_servers(with_bastion, extra_servers),
        }, indent=2))


@dataclasses.dataclass
class K8STfvarsConfig:
    ca_replicas: int = 1
    ca_image: str = None
    ca_extra_global_config: str = None
    ca_nodegroup_configs: dict = None
    ca_nodegroup_rke2_extra_config: dict = None
    ca_extra_args: list = None
    ca_rbac_url: str = None


def write_k8s_tfvars(tfdir, ssh_pubkeys, k8s_version, tfvars_config: K8STfvarsConfig):
    assert not os.path.exists(os.path.join(tfdir, "02-k8s", "ktb.auto.tfvars.json"))
    ssh_pubkeys_ini_encoded = ssh_pubkeys.strip().replace("\n", "\\n")
    ca_image = tfvars_config.ca_image
    if not ca_image:
        assert k8s_version
        ca_image = f'ghcr.io/kamatera/kubernetes-autoscaler:v{k8s_version}'
    ca_global_config = f'\ndefault-ssh-key="{ssh_pubkeys_ini_encoded}"\n'
    if tfvars_config.ca_extra_global_config:
        ca_global_config += f'\n{tfvars_config.ca_extra_global_config}\n'
    ca_nodegroup_configs = tfvars_config.ca_nodegroup_configs
    if not ca_nodegroup_configs:
        ca_nodegroup_configs = {}
    ca_nodegroup_rke2_extra_config = tfvars_config.ca_nodegroup_rke2_extra_config
    if not ca_nodegroup_rke2_extra_config:
        ca_nodegroup_rke2_extra_config = {}
    ca_extra_args = tfvars_config.ca_extra_args
    if not ca_extra_args:
        ca_extra_args = [
            "--cordon-node-before-terminating",
            "--scale-down-unneeded-time=2m",
        ]
    with open(os.path.join(tfdir, "02-k8s", "ktb.auto.tfvars.json"), "w") as f:
        f.write(json.dumps({
            "cluster_autoscaler_version": k8s_version,
            "cluster_autoscaler_replicas": tfvars_config.ca_replicas,
            "cluster_autoscaler_kamatera_api_client_id": config.KAMATERA_API_CLIENT_ID,
            "cluster_autoscaler_kamatera_api_secret": config.KAMATERA_API_SECRET,
            "cluster_autoscaler_image": ca_image,
            "cluster_autoscaler_global_config": ca_global_config,
            "cluster_autoscaler_nodegroup_configs": ca_nodegroup_configs,
            "cluster_autoscaler_nodegroup_rke2_extra_config": ca_nodegroup_rke2_extra_config,
            "cluster_autoscaler_extra_args": ca_extra_args,
            "cluster_autoscaler_rbac_url": tfvars_config.ca_rbac_url,
        }, indent=2))


def generate_name_prefix():
    return f'kca{datetime.datetime.now().strftime("%m%d")}{secrets.token_hex(2)}'


def main(name_prefix=None, k8s_version=None, rke2_version=None, datacenter_id=None, with_bastion=False, k8s_tfvars_config=None, extra_servers=None):
    assert config.KAMATERA_API_CLIENT_ID and config.KAMATERA_API_SECRET
    if name_prefix is None:
        name_prefix = generate_name_prefix()
    ssh_pubkeys = util.get_ssh_pubkeys()
    tfdir = os.path.join(os.path.dirname(__file__), "..", "..", "..")
    print(f'name prefix: {name_prefix}')
    try:
        if k8s_version:
            assert not rke2_version, "cannot specify both k8s_version and rke2_version"
            rke2_version = f'v{k8s_version}'
        else:
            assert rke2_version, "must specify either k8s_version or rke2_version"
        if not datacenter_id:
            datacenter_id = "US-NY2"
        write_rke2_tfvars(tfdir, name_prefix, rke2_version, datacenter_id, ssh_pubkeys, with_bastion, extra_servers)
        subprocess.check_call(["terraform", "init"], cwd=os.path.join(tfdir, "01-rke2"))
        util.wait_for(
            "Terraform apply for rke2 to complete",
            lambda: subprocess.check_call(["terraform", "apply", "-auto-approve"], cwd=os.path.join(tfdir, "01-rke2")) or True,
            retry_on_exception=True
        )
        if k8s_tfvars_config:
            write_k8s_tfvars(tfdir, ssh_pubkeys, k8s_version, k8s_tfvars_config)
            subprocess.check_call(["terraform", "init"], cwd=os.path.join(tfdir, "02-k8s"))
            util.wait_for(
                "Terraform apply for k8s to complete",
                lambda: subprocess.check_call(["terraform", "apply", "-auto-approve"], cwd=os.path.join(tfdir, "02-k8s")) or True,
                retry_on_exception=True
            )
    finally:
        print(f'name prefix: {name_prefix}')
    return name_prefix
