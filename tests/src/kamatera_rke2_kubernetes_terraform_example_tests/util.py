import os
import json
import subprocess
import time
import datetime
import traceback
from textwrap import dedent

from . import destroy, config


def get_ssh_pubkeys():
    return subprocess.check_output(["bash", "-c", "cat ~/.ssh/*.pub"]).decode().strip()


def get_ssh_config(name_prefix=None, bastion_port=None, nodes_port=None, identity_file=None):
    if name_prefix:
        ssh_config = os.path.join(os.path.dirname(__file__), "..", "..", "..", f"ssh_config_{name_prefix}")
        if not identity_file:
            identity_file = os.path.expanduser("~/.ssh/id_rsa")
        if bastion_port:
            bastion_public_ip = None
            for network in destroy.cloudcli("server", "info", "--name", f"{name_prefix}-bastion", parse_json=True)[0]["networks"]:
                if network["network"].startswith("wan-"):
                    bastion_public_ip = network["ips"][0]
                    break
            assert bastion_public_ip
            controlplane_private_ip = None
            for network in destroy.cloudcli("server", "info", "--name", f"{name_prefix}-controlplane1", parse_json=True)[0]["networks"]:
                if network["network"].startswith("lan-"):
                    controlplane_private_ip = network["ips"][0]
                    break
            assert controlplane_private_ip
            with open(ssh_config, "w") as f:
                f.write(dedent(f'''
                    Host {name_prefix}-bastion
                      HostName {bastion_public_ip}
                      User root
                      Port {bastion_port}
                      IdentityFile {identity_file}
                    Host {name_prefix}-controlplane1
                      HostName {controlplane_private_ip}
                      User root
                      Port {nodes_port}
                      ProxyJump {name_prefix}-bastion
                      IdentityFile {identity_file}
                '''))
        else:
            controlplane_public_ip = None
            for network in destroy.cloudcli("server", "info", "--name", f"{name_prefix}-controlplane1", parse_json=True)[0]["networks"]:
                if network["network"].startswith("wan-"):
                    controlplane_public_ip = network["ips"][0]
                    break
            assert controlplane_public_ip
            with open(ssh_config, "w") as f:
                f.write(dedent(f'''
                    Host {name_prefix}-controlplane1
                      HostName {controlplane_public_ip}
                      User root
                      Port {nodes_port}
                      IdentityFile {identity_file}
                '''))
    else:
        ssh_config = os.path.join(os.path.dirname(__file__), "..", "..", "..", "ssh_config")
    return ssh_config


def get_kubeconfig(name_prefix=None, bastion_port=None, nodes_port=None, identity_file=None):
    if name_prefix:
        kubeconfig = os.path.join(os.path.dirname(__file__), "..", "..", "..", f".kubeconfig-{name_prefix}")
        ssh_config = get_ssh_config(name_prefix, bastion_port, nodes_port, identity_file)
        controlplane_public_ip = None
        for network in destroy.cloudcli("server", "info", "--name", f"{name_prefix}-controlplane1", parse_json=True)[0][
            "networks"]:
            if network["network"].startswith("wan-"):
                controlplane_public_ip = network["ips"][0]
                break
        assert controlplane_public_ip
        subprocess.check_call([
            "bash", "-c", f'''
                ssh -F {ssh_config} {name_prefix}-controlplane1 "cat /etc/rancher/rke2/rke2.yaml" > {kubeconfig}
                sed -i 's/127.0.0.1/{controlplane_public_ip}/g' {kubeconfig}
            '''
        ])
    else:
        kubeconfig = os.path.join(os.path.dirname(__file__), "..", "..", "..", ".kubeconfig")
    return kubeconfig


def kubectl(*args, parse_json=False, run=False, timeout_seconds=360, poll_seconds=10, **kwargs):
    if timeout_seconds and poll_seconds:
        state = {}
        wait_for(
            description=f"kubectl {' '.join(args)}",
            condition=lambda: state.update(res=kubectl(*args, parse_json=parse_json, run=run, timeout_seconds=None, poll_seconds=None, **kwargs)) or True,
            retry_on_exception=True,
            timeout_seconds=timeout_seconds,
            poll_seconds=poll_seconds,
        )
        return state["res"]
    else:
        if parse_json:
            assert not run
            func = subprocess.check_output
        elif run:
            func = subprocess.run
        else:
            func = subprocess.check_call
        res = func([
            "kubectl", *args, *(["-o", "json"] if parse_json else [])
        ], env={
            **os.environ,
            "KUBECONFIG": get_kubeconfig(),
        }, text=True, **kwargs)
        if parse_json:
            return json.loads(res)
        elif run:
            return res
        else:
            return None


def wait_for(
    description, condition, timeout_seconds=config.DEFAULT_WAIT_FOR_TIMEOUT_SECONDS, progress=None, poll_seconds=15, retry_on_exception=False,
    print_function=print
):
    start_time = time.time()
    print_function(f'waiting for condition: {description} (with timeout {timeout_seconds} seconds)')
    print_function(f'start time: {datetime.datetime.now().isoformat()}')

    def progress_():
        if progress:
            try:
                res = progress()
                if res is not None:
                    print_function(res)
            except:
                traceback.print_exc()

    i = 0
    while True:
        i += 1
        try:
            res = condition()
        except:
            if retry_on_exception:
                traceback.print_exc()
                res = False
            else:
                raise
        if res:
            print_function(f'condition met: {description}')
            print_function(f'end time: {datetime.datetime.now().isoformat()}')
            progress_()
            return
        if time.time() - start_time > timeout_seconds:
            progress_()
            raise AssertionError(f"timeout waiting for {description}")
        if i % 10 == 0:
            progress_()
        time.sleep(poll_seconds)


def kubectl_node_count(label_selector=None):
    data = kubectl("get", "nodes", *(["-l", label_selector] if label_selector else []), parse_json=True)
    total_nodes = 0
    ready_nodes = 0
    for node in data.get("items", []):
        total_nodes += 1
        for condition in node.get("status", {}).get("conditions", []):
            if condition.get("type") == "Ready" and condition.get("status") == "True":
                ready_nodes += 1
                break
    return total_nodes, ready_nodes


def kubectl_pods_count(namespace):
    pods = kubectl("get", "pods", "-n", namespace, parse_json=True)["items"]
    total = 0
    running = 0
    for pod in pods:
        total += 1
        if pod.get("status", {}).get("phase") == "Running":
            running += 1
    return total, running


def curl_unique_demo_pods(ips, pods):
    start_time = time.time()
    expected_count = len(pods)
    ip_pods = {
        ip: set() for ip in ips
    }
    while not all(len(p) >= expected_count for p in ip_pods.values()):
        for ip in ips:
            if len(ip_pods[ip]) < expected_count:
                try:
                    pod = subprocess.check_output(["curl", "-H", "Host: demo.example.com", "-s", f"http://{ip}/"], text=True).strip()
                except subprocess.CalledProcessError:
                    continue
                assert pod in pods, f"unexpected pod name '{pod}' from ip {ip}"
                ip_pods[ip].add(pod)
        assert time.time() - start_time < 300, "timeout curling demo pods"
    return ip_pods
