from .common import assert_demo_app


def test():
    with assert_demo_app() as (name_prefix, datacenter_id, k8s_version, nodes, demo_pods, node_external_ips):
        pass
