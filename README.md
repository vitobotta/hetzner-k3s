# Create production grade Kubernetes clusters in Hetzner Cloud in just a few minutes

![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/vitobotta/hetzner-k3s)
![GitHub Release Date](https://img.shields.io/github/release-date/vitobotta/hetzner-k3s)
![GitHub last commit](https://img.shields.io/github/last-commit/vitobotta/hetzner-k3s)
![GitHub issues](https://img.shields.io/github/issues-raw/vitobotta/hetzner-k3s)
![GitHub pull requests](https://img.shields.io/github/issues-pr-raw/vitobotta/hetzner-k3s)
![GitHub](https://img.shields.io/github/license/vitobotta/hetzner-k3s)
![GitHub Discussions](https://img.shields.io/github/discussions/vitobotta/hetzner-k3s)
![GitHub top language](https://img.shields.io/github/languages/top/vitobotta/hetzner-k3s)

![GitHub forks](https://img.shields.io/github/forks/vitobotta/hetzner-k3s?style=social)
![GitHub Repo stars](https://img.shields.io/github/stars/vitobotta/hetzner-k3s?style=social)

## What is this?

This is a CLI tool to quickly create and manage Kubernetes clusters in [Hetzner Cloud](https://www.hetzner.com/cloud) using the lightweight Kubernetes distribution [k3s](https://k3s.io/) from [Rancher](https://rancher.com/).

Hetzner Cloud is an awesome cloud provider which offers a truly great service with the best performance/cost ratio in the market. With Hetzner's Cloud Controller Manager and CSI driver you can provision load balancers and persistent volumes very easily.

k3s is my favorite Kubernetes distribution now because it uses much less memory and CPU, leaving more resources to workloads. It is also super quick to deploy because it's a single binary.

Using this tool, creating a highly available k3s cluster with 3 masters for the control plane and 3 worker nodes takes **a few minutes** only. This includes

- creating the infrastructure resources (servers, private network, firewall, load balancer for the API server for HA clusters)
- deploying k3s to the nodes
- installing the [Hetzner Cloud Controller Manager](https://github.com/hetznercloud/hcloud-cloud-controller-manager) to provision load balancers right away
- installing the [Hetzner CSI Driver](https://github.com/hetznercloud/csi-driver) to provision persistent volumes using Hetzner's block storage
- installing the [Rancher System Upgrade Controller](https://github.com/rancher/system-upgrade-controller) to make upgrades to a newer version of k3s easy and quick
- installing the [Cluster Autoscaler](https://github.com/kubernetes/autoscaler) to allow for autoscaling node pools

Also see this [wiki page](https://github.com/vitobotta/hetzner-k3s/wiki/Tutorial:---Setting-up-a-cluster) for a tutorial on how to set up a cluster with the most common setup to get you started.

___
## Who am I?

I'm a Senior Backend Engineer and DevOps based in Finland and working for event management platform [Brella](https://www.brella.io/).

I also write a [technical blog](https://vitobotta.com/) on programming, DevOps and related technologies.

___
## Prerequisites

All that is needed to use this tool is

- an Hetzner Cloud account
- an Hetzner Cloud token: for this you need to create a project from the cloud console, and then an API token with **both read and write permissions** (sidebar > Security > API Tokens); you will see the token only once, so be sure to take note of it somewhere safe
- kubectl installed

___
## Getting started

Before using the tool, be sure to have kubectl installed as it's required to install some software in the cluster to provision load balancers/persistent volumes and perform k3s upgrades.

### macOS

#### With Homebrew

```bash
brew install vitobotta/tap/hetzner_k3s
```

#### Binary installation

You need to install these dependencies first:
- libssh2
- libevent
- bdw-gc
- libyaml

##### Intel

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/latest/hetzner-k3s-mac-amd64
chmod +x hetzner-k3s-mac-x64
sudo mv hetzner-k3s-mac-x64 /usr/local/bin/hetzner-k3s
```

##### Apple Silicon / M1

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/latest/hetzner-k3s-mac-arm64
chmod +x hetzner-k3s-mac-arm
sudo mv hetzner-k3s-mac-arm /usr/local/bin/hetzner-k3s
```

### Linux

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/latest/hetzner-k3s-linux-x86_64
chmod +x hetzner-k3s-linux-x86_64
sudo mv hetzner-k3s-linux-x86_64 /usr/local/bin/hetzner-k3s
```

___

## Creating a cluster

The tool requires a simple configuration file in order to create/upgrade/delete clusters, in the YAML format like in the example below:

```yaml
---
hetzner_token: <your token>
cluster_name: test
kubeconfig_path: "./kubeconfig"
k3s_version: v1.25.5+k3s1
public_ssh_key_path: "~/.ssh/id_rsa.pub"
private_ssh_key_path: "~/.ssh/id_rsa"
use_ssh_agent: false
ssh_allowed_networks:
  - 0.0.0.0/0
api_allowed_networks:
  - 0.0.0.0/0
schedule_workloads_on_masters: false
# image: rocky-9 # optional: default is ubuntu-22.04
# snapshot_os: microos # otional: specified the os type when using a custom snapshot
masters_pool:
  instance_type: cpx21
  instance_count: 3
  location: nbg1
  # labels:
  #   - key: purpose
  #     value: blah
  # taints:
  #   - key: something
  #     value: value1:NoSchedule
worker_node_pools:
- name: small
  instance_type: cpx21
  instance_count: 4
  location: hel1
  # labels:
  #   - key: purpose
  #     value: blah
  # taints:
  #   - key: something
  #     value: value1:NoSchedule
- name: big
  instance_type: cpx31
  instance_count: 2
  location: fsn1
  autoscaling:
    enabled: true
    min_instances: 0
    max_instances: 3
additional_packages:
- somepackage
post_create_commands:
- apt update
- apt upgrade -y
- apt autoremove -y
- shutdown -r now
enable_encryption: true
# existing_network: <specify if you want to use an existing network, otherwise one will be created for this cluster>
# kube_api_server_args:
# - arg1
# - ...
# kube_scheduler_args:
# - arg1
# - ...
# kube_controller_manager_args:
# - arg1
# - ...
# kube_cloud_controller_manager_args:
# - arg1
# - ...
# kubelet_args:
# - arg1
# - ...
# kube_proxy_args:
# - arg1
# - ...
```

It should hopefully be self explanatory; you can run `hetzner-k3s releases` to see a list of the available k3s releases.

If you don't want to specify the Hetzner token in the config file (for example if you want to use the tool with CI), then you can use the `HCLOUD_TOKEN` environment variable instead, which has predecence.

**Important**: The tool assignes the label `cluster` to each server it creates, with the cluster name you specify in the config file, as the value. So please ensure you don't create unrelated servers in the same project having
the label `cluster=<cluster name>`, because otherwise they will be deleted if you delete the cluster. I recommend you create a separate Hetzner project for each cluster, see note at the end of this README for more details.

If you set `masters_pool.instance_count` to 1 then the tool will create a non highly available control plane; for production clusters you may want to set it to a number greater than 1. This number must be odd to avoid split brain issues with etcd and the recommended number is 3.

You can specify any number of worker node pools for example to have mixed nodes with different specs for different workloads.

At the moment Hetzner Cloud has five locations: two in Germany (`nbg1`, Nuremberg and `fsn1`, Falkenstein), one in Finland (`hel1`, Helsinki) and two in the USA (`ash`, Ashburn, Virginia, and `hil`, Hillsboro, Oregon). Please keep in mind that US locations only offer instances with AMD CPUs at the moment.

For the available instance types and their specs, either check from inside a project when adding a server manually or run the following with your Hetzner token:

```bash
curl \
	-H "Authorization: Bearer $API_TOKEN" \
	'https://api.hetzner.cloud/v1/server_types'
```

### Using alternative images

By default, the image in use is `ubuntu-22.04`, but you can specify an image to use with the `image` config option. You can choose from the following images currently available:

- ubuntu-18.04, ubuntu-20.04, ubuntu-22.04
- debian-10, debian-11
- centos-7, centos-stream-8, centos-stream-9
- rocky-8, rocky-9
- fedora-36, fedora-37

It's also possible to use a snapshot that you have already created from an existing server. If you want to use a custom
snapshot you'll need to specify the **ID** of the snapshot/image, not the description you gave when you created the template server. To find
the ID of your custom image/snapshot, run:

```bash
curl \
	-H "Authorization: Bearer $API_TOKEN" \
	'https://api.hetzner.cloud/v1/images'
```

I've tested snapshots for [openSUSE MicroOS](https://microos.opensuse.org/) but others might work too. You can easily create a snapshot for MicroOS using [this tool](https://github.com/kube-hetzner/packer-hcloud-microos). Creating the snapshot takes just a couple of minutes and then you can use it with hetzner-k3s by setting the config option `image` to the **ID** of the snapshot, and `snapshot_os` to `microos`.

### Limitations:

- if you use a snapshot instead of one of the default images, the creation of the servers may take longer than when using a regular image
- the setting `api_allowed_networks` allows specifying which networks can access the Kubernetes API, but this only works with single master clusters currently. Multi-master HA clusters require a load balancer for the API, but load balancers are not yet covered by Hetzner's firewalls
- if you enable autoscaling for one or more nodepools, do not change that setting afterwards as it can cause problems to the autoscaler
- worker nodes created by the autoscaler must be deleted manually from the Hetzner Console when deleting the cluster
- SSH keys with passphrases can only be used if you set `use_ssh_agent` to `true` and use an SSH agent to access your key. To start and agent e.g. on macOS:

```bash
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/<private key>
```

### Installation

Finally, to create the cluster run:

```bash
hetzner-k3s create --config cluster_config.yaml
```

This will take a few minutes depending on the number of masters and worker nodes.


### Idempotency

The `create` command can be run any number of times with the same configuration without causing any issue, since the process is idempotent. This means that if for some reason the create process gets stuck or throws errors (for example if the Hetzner API is unavailable or there are timeouts etc), you can just stop the current command, and re-run it with the same configuration to continue from where it left.

### Adding nodes

To add one or more nodes to a node pool, just change the instance count in the configuration file for that node pool and re-run the create command.

**Important**: if you are increasing the size of a node pool created prior to v0.5.7, please see [this thread](https://github.com/vitobotta/hetzner-k3s/issues/80).

### Scaling down a node pool

To make a node pool smaller:

- decrease the instance count for the node pool in the configuration file so that those extra nodes are not recreated in the future
- delete the nodes from Kubernetes (`kubectl delete node <name>`)
- delete the instances from the cloud console (make sure you delete the correct ones :p)

In a future release I will add some automation for the cleanup.

### Replacing a problematic node

- delete the node from Kubernetes (`kubectl delete node <name>`)
- delete the correct instance from the cloud console
- re-run the create script. This will re-create the missing node and have it join to the cluster


### Converting a non-HA cluster to HA

It's easy to convert a non-HA with a single master cluster to HA with multiple masters. Just change the masters instance count and re-run the create command. This will create a load balancer for the API server and update the kubeconfig so that all the API requests go through the load balancer.

___
## Upgrading to a new version of k3s

If it's the first time you upgrade the cluster, all you need to do to upgrade it to a newer version of k3s is run the following command:

```bash
hetzner-k3s upgrade --config cluster_config.yaml --new-k3s-version v1.21.3+k3s1
```

So you just need to specify the new k3s version as an additional parameter and the configuration file will be updated with the new version automatically during the upgrade. To see the list of available k3s releases run the command `hetzner-k3s releases`.

Note that the API server will briefly be unavailable during the upgrade of the controlplane.

To check the upgrade progress, run `watch kubectl get nodes -owide`. You will see the masters being upgraded one per time, followed by the worker nodes.

### What to do if the upgrade doesn't go smoothly

If the upgrade gets stuck for some reason, or it doesn't upgrade all the nodes:

1. Clean up the existing upgrade plans and jobs, and restart the upgrade controller

```bash
kubectl -n system-upgrade delete job --all
kubectl -n system-upgrade delete plan --all

kubectl label node --all plan.upgrade.cattle.io/k3s-server- plan.upgrade.cattle.io/k3s-agent-

kubectl -n system-upgrade rollout restart deployment system-upgrade-controller
kubectl -n system-upgrade rollout status deployment system-upgrade-controller
```

I recommend running the above commands also when upgrading a cluster that has already been upgraded at least once previously, since the upgrade leaves some stuff behind that needs to be cleaned up.

You can also check the logs of the system upgrade controller's pod:

```bash
kubectl -n system-upgrade \
  logs -f $(kubectl -n system-upgrade get pod -l pod-template-hash -o jsonpath="{.items[0].metadata.name}")
```

A final note about upgrades is that if for some reason the upgrade gets stuck after upgrading the masters and before upgrading the worker nodes, just cleaning up the resources as described above might not be enough. In that case also try running the following to tell the upgrade job for the workers that the masters have already been upgraded, so the upgrade can continue for the workers:

```bash
kubectl label node <master1> <master2> <master2> plan.upgrade.cattle.io/k3s-server=upgraded
```
___
## Upgrading the OS on nodes

- consider adding a temporary node during the process if you don't have enough spare capacity in the cluster
- drain one node
- update etc
- reboot
- uncordon
- proceed with the next node

___
## Deleting a cluster

To delete a cluster, running

```bash
hetzner-k3s delete --config cluster_config.yaml
```

This will delete all the resources in the Hetzner Cloud project for the cluster being deleted.

## Troubleshooting

See [this page](https://github.com/vitobotta/hetzner-k3s/wiki/Troubleshooting) for solutions to common issues.

___
## Additional info

### Load balancers

Once the cluster is ready, you can already provision services of type LoadBalancer for your workloads (such as the Nginx ingress controller for example) thanks to the Hetzner Cloud Controller Manager that is installed automatically.

There are some annotations that you can add to your services to configure the load balancers. I personally use the following:

```yaml
  service:
    annotations:
      load-balancer.hetzner.cloud/hostname: <a valid fqdn>
      load-balancer.hetzner.cloud/http-redirect-https: 'false'
      load-balancer.hetzner.cloud/location: nbg1
      load-balancer.hetzner.cloud/name: <lb name>
      load-balancer.hetzner.cloud/uses-proxyprotocol: 'true'
      load-balancer.hetzner.cloud/use-private-ip: "true"
```

I set `load-balancer.hetzner.cloud/hostname` to a valid hostname that I configure (after creating the load balancer) with the IP of the load balancer; I use this together with the annotation `load-balancer.hetzner.cloud/uses-proxyprotocol: 'true'` to enable the proxy protocol. Reason: I enable the proxy protocol on the load balancers so that my ingress controller and applications can "see" the real IP address of the client. However when this is enabled, there is a problem where [cert-manager](https://cert-manager.io/docs/) fails http01 challenges; you can find an explanation of why [here](https://github.com/compumike/hairpin-proxy) but the easy fix provided by some providers - including Hetzner - is to configure the load balancer so that it uses a hostname instead of an IP. Again, read the explanation for the reason but if you care about seeing the actual IP of the client then I recommend you use these two annotations.

The annotation `load-balancer.hetzner.cloud/use-private-ip: "true"` ensures that the communication between the load balancer and the nodes happens through the private network, so we don't have to open any ports on the nodes (other than the port 6443 for the Kubernetes API server).

The other annotations should be self explanatory. You can find a list of the available annotations [here](https://pkg.go.dev/github.com/hetznercloud/hcloud-cloud-controller-manager/internal/annotation).

### Persistent volumes

Once the cluster is ready you can create persistent volumes out of the box with the default storage class `hcloud-volumes`, since the Hetzner CSI driver is installed automatically. This will use Hetzner's block storage (based on Ceph so it's replicated and highly available) for your persistent volumes. Note that the minimum size of a volume is 10Gi. If you specify a smaller size for a volume, the volume will be created with a capacity of 10Gi anyway.

### Keeping a project per cluster

I recommend that you create a separate Hetzner project for each cluster, because otherwise multiple clusters will attempt to create overlapping routes. I will make the pod cidr configurable in the future to avoid this, but I still recommend keeping clusters separated from each other. This way, if you want to delete a cluster with all the resources created for it, you can just delete the project.

___
## Contributing and support

Please create a PR if you want to propose any changes, or open an issue if you are having trouble with the tool - I will do my best to help if I can.

Contributors:

- [TitanFighter](https://github.com/TitanFighter) for [this awesome tutorial](https://github.com/vitobotta/hetzner-k3s/wiki/Tutorial:---Setting-up-a-cluster)

___
## License

This tool is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

___
## Code of conduct

Everyone interacting in the hetzner-k3s project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/vitobotta/hetzner-k3s/blob/main/CODE_OF_CONDUCT.md).


## Stargazers over time

[![Stargazers over time](https://starchart.cc/vitobotta/hetzner-k3s.svg)](https://starchart.cc/vitobotta/hetzner-k3s)
