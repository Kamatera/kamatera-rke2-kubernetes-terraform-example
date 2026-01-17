from kamatera_rke2_kubernetes_terraform_example_tests import k8s_demo_app


def test():
    with k8s_demo_app.assert_demo_app() as (name_prefix, datacenter_id, k8s_version, nodes, demo_pods, node_external_ips):
        pass
