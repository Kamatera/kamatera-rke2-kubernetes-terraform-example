import os
import json
import subprocess
import traceback

from . import config


def cloudcli(*args, parse_json=False, run=False, popen=False, **kwargs):
    if parse_json:
        assert not run and not popen
        func = subprocess.check_output
    elif run:
        assert not popen
        func = subprocess.run
    elif popen:
        func = subprocess.Popen
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
    errors = []
    poweroff_servers = []
    terminate_servers = []
    for server in cloudcli("server", "list", parse_json=True):
        if server["name"].startswith(name_prefix):
            if server.get("power") == "on":
                poweroff_servers.append(server["name"])
            else:
                terminate_servers.append(server["name"])
    print(f'Found {len(poweroff_servers)} servers to power off')
    print(f'Found {len(terminate_servers)} servers to terminate')
    processes = {}
    for server_name in poweroff_servers:
        print(f"Powering off server {server_name}...")
        processes[server_name] = cloudcli("server", "poweroff", "--name", server_name, "--wait", popen=True)
    for server_name, process in processes.items():
        res = process.wait()
        if res != 0:
            errors.append(f'Failed to poweroff server: {server_name} (exit code {res})')
    processes = {}
    for server_name in [*terminate_servers, *poweroff_servers]:
        print(f"Terminating server {server_name}...")
        processes[server_name] = cloudcli("server", "terminate", "--name", server_name, "--force", "--wait", popen=True)
    for server_name, process in processes.items():
        res = process.wait()
        if res != 0:
            errors.append(f'Failed to terminate server: {server_name} (exit code {res})')
    return errors


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


def main(name_prefix=None, datacenter_id=None, force=False):
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
    assert datacenter_id
    errors = []
    errors += terminate_servers(name_prefix)
    if "," in datacenter_id:
        datacenter_ids = [dc.strip() for dc in datacenter_id.split(",")]
    else:
        datacenter_ids = [datacenter_id]
    for dc_id in datacenter_ids:
        errors += terminate_networks(dc_id, name_prefix)
    if errors and not force:
        raise Exception("Errors occurred during termination:\n" + "\n".join(errors))
    subprocess.check_call(["bash", "-c", '''
        rm -f */*.auto.tfvars.json
        rm -rf */terraform.tfstate*
        rm -rf */.terraform*
        rm -rf */ssh_known_hosts.*
        rm -f .kubeconfig ssh_config ssh_known_hosts .cluster_token
    '''], cwd=tfdir)
    print("Destroyed all resources.")
    if errors:
        raise Exception("Errors occurred during termination:\n" + "\n".join(errors))
