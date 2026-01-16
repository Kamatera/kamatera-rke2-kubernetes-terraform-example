import os
import json
import subprocess

from . import config


def cloudcli(*args, parse_json=False, run=False, **kwargs):
    if parse_json:
        assert not run
        func = subprocess.check_output
    elif run:
        func = subprocess.run
    else:
        func = subprocess.check_call
    res = func([
        "cloudcli", *args, *(["--format", "json"] if parse_json else [])
    ], env={
        **os.environ,
        "CLOUDCLI_APICLIENTID": config.KAMATERA_API_CLIENT_ID,
        "CLOUDCLI_APISECRET": config.KAMATERA_API_SECRET,
    }, text=True, **kwargs)
    return json.loads(res) if parse_json else res


def terminate_servers(name_prefix):
    while True:
        print("Terminating servers...")
        res = cloudcli("server", "terminate", "--force", "--name", f'{name_prefix}.*', "--wait", run=True, capture_output=True)
        print(res.stdout)
        print(res.stderr)
        if res.returncode != 0:
            if 'No servers found' in res.stdout:
                break
            else:
                raise Exception(f"Failed to terminate servers")


def terminate_networks(datacenter_id, name_prefix):
    print(f"Terminating networks for datacenter_id {datacenter_id}...")
    errors = []
    network_vlan_ids = set()
    network_ids = set()
    for network in cloudcli("network", "list", "--datacenter", datacenter_id, parse_json=True):
        for name in network['names']:
            if name_prefix in name:
                network_vlan_ids.add(network["vlanId"])
                for id_ in network["ids"]:
                    network_ids.add(id_)
    for network_vlan_id in network_vlan_ids:
        for subnet in cloudcli("network", "subnet_list", "--vlanId", str(network_vlan_id), "--datacenter", datacenter_id, parse_json=True):
            res = cloudcli("network", "subnet_delete", "--subnetId", str(subnet["subnetId"]), run=True)
            if res.returncode != 0:
                errors.append(f'Failed to delete subnet {subnet["subnetId"]} in vlan {network_vlan_id} in datacenter {datacenter_id}')
    for network_id in network_ids:
        res = cloudcli("network", "delete", "--id", str(network_id), "--datacenter", datacenter_id, run=True)
        if res.returncode != 0:
            errors.append(f'Failed to delete network {network_id} in datacenter {datacenter_id}')
    return errors


def main(name_prefix=None, datacenter_id=None):
    tfdir = os.path.join(os.path.dirname(__file__), "..", "..", "..")
    if not name_prefix or not datacenter_id:
        if os.path.exists(os.path.join(tfdir, "01-rke2", "ktb.auto.tfvars.json")):
            with open(os.path.join(tfdir, "01-rke2", "ktb.auto.tfvars.json")) as f:
                tfvars = json.load(f)
                if not name_prefix:
                    name_prefix = tfvars.get("name_prefix")
                if not datacenter_id:
                    datacenter_id = tfvars.get("datacenter_id")
    assert name_prefix
    terminate_servers(name_prefix)
    assert datacenter_id
    if "," in datacenter_id:
        datacenter_ids = [dc.strip() for dc in datacenter_id.split(",")]
    else:
        datacenter_ids = [datacenter_id]
    errors = []
    for dc_id in datacenter_ids:
        errors += terminate_networks(dc_id, name_prefix)
    if errors:
        raise Exception("Errors occurred during network termination:\n" + "\n".join(errors))
    subprocess.check_call(["bash", "-c", '''
        rm -f */*.auto.tfvars.json
        rm -rf */terraform.tfstate*
        rm -rf */.terraform*
        rm -rf */ssh_known_hosts.*
        rm -f .kubeconfig ssh_config ssh_known_hosts .cluster_token
    '''], cwd=tfdir)
    print("Destroyed all resources.")
