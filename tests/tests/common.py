import os
from contextlib import contextmanager

from kamatera_rke2_kubernetes_terraform_example_tests import setup, util, destroy


@contextmanager
def assert_demo_app(with_bastion=True, extra_servers=None):
    name_prefix = setup.generate_name_prefix()
    datacenter_id = os.getenv("DATACENTER_ID") or "IL"
    k8s_version = os.getenv("K8S_VERSION") or "1.35"
    high_availability = os.getenv("HIGH_AVAILABILITY") == "yes"
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
            extra_servers[f"controlplane{i+2}"] = {
                "role": "rke2",
                "role_config": {
                    "rke2_type": "server"
                },
                "cpu_cores": 4,
                "ram_mb": 8192,
            }
    try:
        setup.main(
            name_prefix=name_prefix,
            k8s_version=k8s_version,
            datacenter_id=datacenter_id,
            with_bastion=with_bastion,
            extra_servers=extra_servers,
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
            lambda: util.kubectl("apply", "-f", "k8s_demo_app.yaml", cwd=os.path.join(os.path.dirname(__file__))) or True,
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
        print(util.curl_unique_demo_pods(node_external_ips, demo_pods))
        yield name_prefix, datacenter_id, k8s_version, nodes, demo_pods, node_external_ips
    except:
        raise
    else:
        destroy.main(
            name_prefix=name_prefix,
            datacenter_id=datacenter_id,
        )
