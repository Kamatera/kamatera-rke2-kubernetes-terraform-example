import json

import click



@click.group()
def main():
    pass


@main.command()
@click.option("--name-prefix")
@click.option("--k8s-version")
@click.option("--rke2-version")
@click.option("--datacenter-id")
@click.option("--with-bastion", is_flag=True)
@click.option("--k8s-tfvars-config-json")
@click.option("--extra-servers-json")
def setup(**kwargs):
    from . import setup
    k8s_tfvars_config_json = kwargs.pop("k8s_tfvars_config_json")
    if k8s_tfvars_config_json:
        kwargs["k8s_tfvars_config"] = setup.K8STfvarsConfig(**json.loads(k8s_tfvars_config_json))
    extra_servers_json = kwargs.pop("extra_servers_json")
    if extra_servers_json:
        kwargs["extra_servers"] = json.loads(extra_servers_json)
    setup.main(**kwargs)


@main.command()
@click.option("--name-prefix")
@click.option("--datacenter-id")
@click.option("--force", is_flag=True)
def destroy(**kwargs):
    from . import destroy
    destroy.main(**kwargs)


@main.command()
@click.option('--name-prefix')
@click.option("--bastion-port")
@click.option("--nodes-port")
@click.option('--identity-file')
def get_kubeconfig(**kwargs):
    from . import util
    print(util.get_kubeconfig(**kwargs))


@main.command()
@click.option('--name-prefix')
@click.option("--bastion-port")
@click.option("--nodes-port")
@click.option('--identity-file')
def get_ssh_config(**kwargs):
    from . import util
    print(util.get_ssh_config(**kwargs))


@main.command()
@click.argument('args', nargs=-1)
def kubectl(args):
    from . import util
    util.kubectl(*args)
