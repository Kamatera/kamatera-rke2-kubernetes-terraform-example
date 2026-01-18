from kamatera_rke2_kubernetes_terraform_example_tests import k8s_demo_app


def test():
    with k8s_demo_app.assert_demo_app() as (name_prefix, datacenter_id, k8s_version, nodes, demo_pods, node_external_ips):
        print(f'name_prefix="{name_prefix}"')
        print(f'datacenter_id="{datacenter_id}"')
        print(f'k8s_version="{k8s_version}"')
        print(f'nodes={nodes}')
        print(f'demo_pods={demo_pods}')
        print(f'node_external_ips={node_external_ips}')
        print("Great Success! All tests passed.")
