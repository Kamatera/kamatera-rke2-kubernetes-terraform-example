import os
import json
import time
from textwrap import dedent
from contextlib import contextmanager
from ruamel.yaml import YAML

from . import setup, util, destroy


yaml = YAML(typ='safe', pure=True)


def get_extra_servers(extra_servers, high_availability):
    extra_servers = {
        "worker1": {
            "role": "rke2",
            "role_config": {
                "rke2_type": "agent"
            },
            "cpu_cores": 2,
            "ram_mb": 4096,
        },
        "worker2": {
            "role": "rke2",
            "role_config": {
                "rke2_type": "agent"
            },
            "cpu_cores": 2,
            "ram_mb": 4096,
        },
        **(extra_servers or {})
    }
    if high_availability:
        for i in range(2):
            extra_servers[f"controlplane{i + 2}"] = {
                "role": "rke2",
                "role_config": {
                    "rke2_type": "server"
                },
                "cpu_cores": 4,
                "ram_mb": 8192,
            }
    return extra_servers


def get_k8s_tfvars(cluster_autoscaler_image, ca_replicas):
    return setup.K8STfvarsConfig(
        ca_rbac_url='https://raw.githubusercontent.com/Kamatera/kubernetes-autoscaler/refs/heads/kamatera-cluster-autoscaler/cluster-autoscaler/cloudprovider/kamatera/examples/rbac.yaml',
        ca_image=cluster_autoscaler_image,
        ca_replicas=ca_replicas,
        ca_extra_args=[
            "--cordon-node-before-terminating",
            # we set low thresholds for faster testing
            "--scale-down-unneeded-time=1m",
            "--initial-node-group-backoff-duration=1m",
            "--max-node-group-backoff-duration=2m",
            "--node-group-backoff-reset-timeout=5m",
            "--provisioning-request-max-backoff-time=5m",
            "--scale-down-delay-after-add=1m",
            "--scale-down-delay-after-failure=1m",
            "--scale-down-unready-time=2m",
        ],
        ca_nodegroup_configs={
            "autoscaler": dedent('''
                min-size = 1
                max-size = 3
                cpu = 2B
                ram = 2048
                disk = size=20
                template-label = "kubernetes.io/os=linux"
                template-label = "role=autoscaler"
            '''),
        },
        ca_nodegroup_rke2_extra_config={
            "autoscaler": dedent('''
                node-label:
                  - role=autoscaler
            ''')
        },
    )


@contextmanager
def assert_demo_app(extra_servers=None):
    use_existing_name_prefix = os.getenv("USE_EXISTING_NAME_PREFIX")
    name_prefix = use_existing_name_prefix or setup.generate_name_prefix()
    print(f'name_prefix="{name_prefix}"')
    datacenter_id = os.getenv("DATACENTER_ID") or "IL"
    k8s_version = os.getenv("K8S_VERSION") or "1.35"
    high_availability = os.getenv("HIGH_AVAILABILITY") == "yes"
    cluster_autoscaler_image = os.getenv("CLUSTER_AUTOSCALER_IMAGE") or 'ghcr.io/kamatera/kubernetes-autoscaler:kamatera-cluster-autoscaler'
    keep_cluster = os.getenv("KEEP_CLUSTER") == "yes"
    with_bastion = os.getenv("WITH_BASTION") != "no"
    try:
        extra_servers = get_extra_servers(extra_servers, high_availability)
        if use_existing_name_prefix:
            util.kubectl("delete", "namespace", "demo", "--ignore-not-found", "--wait")
            util.kubectl("scale", "deployment", "cluster-autoscaler", "-n", "kube-system", "--replicas=0")
            destroy.cloudcli("server", "terminate", "--force", "--name", f"{name_prefix}-autoscaler-.*", "--wait", run=True)
            util.kubectl("delete", "nodes", "-l", "role=autoscaler", "--wait")
        else:
            setup.main(
                name_prefix=name_prefix,
                k8s_version=k8s_version,
                datacenter_id=datacenter_id,
                with_bastion=with_bastion,
                extra_servers=extra_servers,
                k8s_tfvars_config=get_k8s_tfvars(cluster_autoscaler_image, 0)
            )
        expected_ready_nodes = 1 + len(extra_servers)
        util.wait_for(
            f"{expected_ready_nodes} nodes to be ready",
            lambda: util.kubectl_node_count() == (expected_ready_nodes,expected_ready_nodes),
            progress=lambda: util.kubectl("get", "nodes"),
            retry_on_exception=True
        )
        nodes = util.kubectl("get", "nodes", parse_json=True)["items"]
        assert {node["metadata"]["name"] for node in nodes} == {
            "controlplane1", *extra_servers.keys()
        }
        util.wait_for(
            "deployment of k8s_demo_app",
            lambda: util.kubectl("apply", "-f", "k8s_demo_app.yaml", cwd=os.path.dirname(__file__)) or True,
            retry_on_exception=True
        )
        util.wait_for(
            "2 pods to be running",
            lambda: util.kubectl_pods_count("demo") == (2,2),
            progress=lambda: util.kubectl("get", "pods", "-n", "demo")
        )
        node_external_ips = [
            node["metadata"]["annotations"]["rke2.io/external-ip"]
            for node in nodes
            if node["metadata"]["name"].startswith("worker")
        ]
        demo_pods = set([
            pod["metadata"]["name"]
            for pod in util.kubectl("get", "pods", "-n", "demo", parse_json=True)["items"]
        ])
        assert len(demo_pods) == 2
        util.wait_for(
            "ingress reachable from all IPs to all demo pods",
            lambda: util.curl_unique_demo_pods(node_external_ips, demo_pods) or True,
            progress=lambda: util.curl_unique_demo_pods(node_external_ips, demo_pods),
            retry_on_exception=True
        )
        with open(os.path.join(os.path.dirname(__file__), "k8s_demo_app.yaml")) as f:
            for obj in yaml.load_all(f):
                if obj["kind"] == "Deployment":
                    k8s_demo_app = obj
                    break
        k8s_demo_app['spec']['template']['spec']['nodeSelector'] = {"role": "autoscaler"}
        p = util.kubectl("apply", "-f", "-", run=True, input=json.dumps(k8s_demo_app))
        assert p.returncode == 0
        util.wait_for(
            "3 pods total but only 2 running (due to scheduling on autoscaler nodes)",
            lambda: util.kubectl_pods_count("demo") == (3,2),
            progress=lambda: util.kubectl("get", "pods", "-n", "demo")
        )
        util.kubectl("scale", "deployment", "cluster-autoscaler", "-n", "kube-system", "--replicas=1")
        expected_ready_nodes += 2
        util.wait_for(
            f"{expected_ready_nodes} nodes to be ready",
            lambda: util.kubectl_node_count() == (expected_ready_nodes,expected_ready_nodes),
            progress=lambda: util.kubectl("get", "nodes"),
            retry_on_exception=True
        )
        node_names = {node["metadata"]["name"] for node in util.kubectl("get", "nodes", parse_json=True)["items"]}
        node_names.remove("controlplane1")
        for name in extra_servers.keys():
            node_names.remove(name)
        assert len(node_names) == 2 and all(name.startswith(f"{name_prefix}-autoscaler-") for name in node_names), node_names
        util.wait_for(
            "2 pods total and running (after autoscaler adds nodes)",
            lambda: util.kubectl_pods_count("demo") == (2, 2),
            progress=lambda: util.kubectl("get", "pods", "-n", "demo")
        )
        pods = util.kubectl("get", "pods", "-n", "demo", parse_json=True)["items"]
        assert len(pods) == 2 and all(pod["spec"]["nodeName"].startswith(f"{name_prefix}-autoscaler-") for pod in pods), pods
        for i in range(10):
            print(f'Ensuring autoscaler nodes are stable ({i + 1}/10)...')
            time.sleep(60)
            if util.kubectl_node_count() != (expected_ready_nodes, expected_ready_nodes):
                util.kubectl("get", "nodes")
                raise Exception("Unexpected node count")
            if util.kubectl_pods_count("demo") != (2, 2):
                util.kubectl("get", "pods", "-n", "demo")
                raise Exception("Unexpected pod count")
        util.kubectl("scale", "deployment", "demo", "-n", "demo", "--replicas=0")
        util.wait_for(
            "all demo pods terminated",
            lambda: util.kubectl_pods_count("demo") == (0, 0),
            progress=lambda: util.kubectl("get", "pods", "-n", "demo")
        )
        expected_total_nodes = expected_ready_nodes
        expected_ready_nodes -= 1
        util.wait_for(
            f"{expected_total_nodes} total nodes, {expected_ready_nodes} ready nodes",
            lambda: util.kubectl_node_count() == (expected_total_nodes, expected_ready_nodes),
            progress=lambda: util.kubectl("get", "nodes"),
        )
        yield name_prefix, datacenter_id, k8s_version, nodes, demo_pods, node_external_ips
    except:
        util.kubectl("logs", "-n", "kube-system", "deployment/cluster-autoscaler")
        util.kubectl("get", "nodes")
        util.kubectl("get", "pods", "-n", "demo")
        print(f'name_prefix="{name_prefix}"')
        raise
    else:
        if keep_cluster:
            print(f'name_prefix="{name_prefix}"')
        else:
            destroy.main(
                name_prefix=name_prefix,
                datacenter_id=datacenter_id,
            )
