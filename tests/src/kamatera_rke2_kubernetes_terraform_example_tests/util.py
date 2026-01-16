import os
import json
import subprocess
import time
import datetime
import traceback


def get_ssh_pubkeys():
    return subprocess.check_output(["bash", "-c", "cat ~/.ssh/*.pub"]).decode().strip()


def get_kubeconfig():
    return os.path.join(os.path.dirname(__file__), "..", "..", "..", ".kubeconfig")


def kubectl(*args, parse_json=False, run=False, **kwargs):
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


def wait_for(description, condition, timeout_seconds=900, progress=None, poll_seconds=15, retry_on_exception=False):
    start_time = time.time()
    print(f'waiting for condition: {description} (with timeout {timeout_seconds} seconds)')
    print(f'start time: {datetime.datetime.now().isoformat()}')

    def progress_():
        if progress:
            try:
                res = progress()
                if res is not None:
                    print(res)
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
            print(f'condition met: {description}')
            print(f'end time: {datetime.datetime.now().isoformat()}')
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
