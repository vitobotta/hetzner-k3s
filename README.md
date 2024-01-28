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

---

# The easiest way to create production grade Kubernetes clusters in Hetzner Cloud



## What is this?

This is a CLI tool to quickly create and manage Kubernetes clusters in [Hetzner Cloud](https://www.hetzner.com/cloud) using the lightweight Kubernetes distribution [k3s](https://k3s.io/) from [Rancher](https://rancher.com/).

Hetzner Cloud is an awesome cloud provider which offers a truly great service with the best performance/cost ratio in the market and locations in both Europe and USA.

k3s is my favorite Kubernetes distribution because it uses much less memory and CPU, leaving more resources to workloads. It is also super quick to deploy and upgrade because it's a single binary.

Using `hetzner-k3s`, creating a highly available k3s cluster with 3 masters for the control plane and 3 worker nodes takes **2-3 minutes** only. This includes

- creating all the infrastructure resources (servers, private network, firewall, load balancer for the API server for HA clusters)
- deploying k3s to the nodes
- installing the [Hetzner Cloud Controller Manager](https://github.com/hetznercloud/hcloud-cloud-controller-manager) to provision load balancers right away
- installing the [Hetzner CSI Driver](https://github.com/hetznercloud/csi-driver) to provision persistent volumes using Hetzner's block storage
- installing the [Rancher System Upgrade Controller](https://github.com/rancher/system-upgrade-controller) to make upgrades to a newer version of k3s easy and quick
- installing the [Cluster Autoscaler](https://github.com/kubernetes/autoscaler) to allow for autoscaling node pools

Also see this [wiki page](https://github.com/vitobotta/hetzner-k3s/blob/main/wiki/Setting%20up%20a%20cluster.md) for a tutorial on how to set up a cluster with the most common setup to get you started.



If you like this project and would like to help its development, consider [becoming a sponsor](https://github.com/sponsors/vitobotta).



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
## Installation

Before using the tool, be sure to have kubectl installed as it's required to install some components in the cluster and perform k3s upgrades.

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
- pcre
- gmp

##### Intel

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v1.1.5/hetzner-k3s-macos-amd64
chmod +x hetzner-k3s-macos-amd64
sudo mv hetzner-k3s-macos-amd64 /usr/local/bin/hetzner-k3s
```

##### Apple Silicon / M1

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v1.1.5/hetzner-k3s-macos-arm64
chmod +x hetzner-k3s-macos-arm64
sudo mv hetzner-k3s-macos-arm64 /usr/local/bin/hetzner-k3s
```

### Linux

#### amd64

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v1.1.5/hetzner-k3s-linux-amd64
chmod +x hetzner-k3s-linux-amd64
sudo mv hetzner-k3s-linux-amd64 /usr/local/bin/hetzner-k3s
```

#### arm

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v1.1.5/hetzner-k3s-linux-arm64
chmod +x hetzner-k3s-linux-arm64
sudo mv hetzner-k3s-linux-arm64 /usr/local/bin/hetzner-k3s
```

### Windows

I recommend using the Linux binary under [WSL](https://learn.microsoft.com/en-us/windows/wsl/install).



___

## Creating a cluster

The tool requires a simple configuration file in order to create/upgrade/delete clusters, in the YAML format like in the example below (commented lines are for optional settings):

```yaml
---
hetzner_token: <your token>
cluster_name: test
kubeconfig_path: "./kubeconfig"
k3s_version: v1.26.4+k3s1
public_ssh_key_path: "~/.ssh/id_rsa.pub"
private_ssh_key_path: "~/.ssh/id_rsa"
use_ssh_agent: false # set to true if your key has a passphrase or if SSH connections don't work or seem to hang without agent. See https://github.com/vitobotta/hetzner-k3s#limitations
# ssh_port: 22
ssh_allowed_networks:
  - 0.0.0.0/0 # ensure your current IP is included in the range
api_allowed_networks:
  - 0.0.0.0/0 # ensure your current IP is included in the range
private_network_subnet: 10.0.0.0/16 # ensure this doesn't overlap with other networks in the same project
disable_flannel: false # set to true if you want to install a different CNI
schedule_workloads_on_masters: false
# cluster_cidr: 10.244.0.0/16 # optional: a custom IPv4/IPv6 network CIDR to use for pod IPs
# service_cidr: 10.43.0.0/16 # optional: a custom IPv4/IPv6 network CIDR to use for service IPs
# cluster_dns: 10.43.0.10 # optional: IPv4 Cluster IP for coredns service. Needs to be an address from the service_cidr range
# enable_public_net_ipv4: false # default is true
# enable_public_net_ipv6: false # default is true
# image: rocky-9 # optional: default is ubuntu-22.04
# autoscaling_image: 103908130 # optional, defaults to the `image` setting
# snapshot_os: microos # optional: specified the os type when using a custom snapshot
cloud_controller_manager_manifest_url: "https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/v1.18.0/ccm-networks.yaml"
csi_driver_manifest_url: "https://raw.githubusercontent.com/hetznercloud/csi-driver/v2.5.1/deploy/kubernetes/hcloud-csi.yml"
system_upgrade_controller_manifest_url: "https://raw.githubusercontent.com/rancher/system-upgrade-controller/master/manifests/system-upgrade-controller.yaml"
masters_pool:
  instance_type: cpx21
  instance_count: 3
  location: nbg1
worker_node_pools:
- name: small-static
  instance_type: cpx21
  instance_count: 4
  location: hel1
  # image: debian-11
  # labels:
  #   - key: purpose
  #     value: blah
  # taints:
  #   - key: something
  #     value: value1:NoSchedule
- name: big-autoscaled
  instance_type: cpx31
  instance_count: 2
  location: fsn1
  autoscaling:
    enabled: true
    min_instances: 0
    max_instances: 3
# additional_packages:
# - somepackage
# post_create_commands:
# - apt update
# - apt upgrade -y
# - apt autoremove -y
# enable_encryption: true
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
# api_server_hostname: k8s.example.com # optional: DNS for the k8s API LoadBalancer. After the script has run, create a DNS record with the address of the API LoadBalancer.
```

Most settings should be self explanatory; you can run `hetzner-k3s releases` to see a list of the available k3s releases.

If you don't want to specify the Hetzner token in the config file (for example if you want to use the tool with CI or want to safely commit the config file to a repository), then you can use the `HCLOUD_TOKEN` environment variable instead, which has precedence.

If you set `masters_pool.instance_count` to 1 then the tool will create a non highly available control plane; for production clusters you may want to set it to a number greater than 1. This number must be odd to avoid split brain issues with etcd and the recommended number is 3.

You can specify any number of worker node pools, static or autoscaled, and have mixed nodes with different specs for different workloads.

Hetzner cloud init settings (`additional_packages` & `post_create_commands`) can be defined in the configuration file at root level as well as for each pool if different settings are needed for different pools. If these settings are configured for a pool, these override the settings at root level.

At the moment Hetzner Cloud has five locations: two in Germany (`nbg1`, Nuremberg and `fsn1`, Falkenstein), one in Finland (`hel1`, Helsinki) and two in the USA (`ash`, Ashburn, Virginia, and `hil`, Hillsboro, Oregon). Please keep in mind that US locations only offer instances with AMD CPUs at the moment, while the newly introduced ARM instances are only available in Falkenstein-fsn1 for now.

For the available instance types and their specs, either check from inside a project when adding a server manually or run the following with your Hetzner token:

```bash
curl -H "Authorization: Bearer $API_TOKEN" 'https://api.hetzner.cloud/v1/server_types'
```



To create the cluster run:

```bash
hetzner-k3s create --config cluster_config.yaml
```

This will take a few minutes depending on the number of masters and worker nodes.

### Disabling public IPs (IPv4 or IPv6 or both) on nodes

With `enable_public_net_ipv4: false` and `enable_public_net_ipv6: false` you can disable the public interface for all nodes for improved security and saving on ipv4 addresses costs. These settings are global and effects all master and worker nodes. If you disable public IPs be sure to run hetzer-k3s from a machine that has access to the same private network as the nodes either directly or via some VPN.
Additional networking setup is required via cloud init, so it's important that the machine from which you run hetzner-k3s have internet access and DNS configured correctly, otherwise the cluster creation process will get stuck after creating the nodes. See [this discussion](https://github.com/vitobotta/hetzner-k3s/discussions/252) for additional information and instructions.

### Using alternative OS images

By default, the image in use is `ubuntu-22.04` for all the nodes, but you can specify a different default image with the root level `image` config option or even different images for different static node pools by setting the `image` config option in each node pool. This way you can, for example, have some node pools with ARM instances use the correct OS image for ARM. To do this and use say Ubuntu 22.04 on ARM instances, set `image` to `103908130` with a specific image ID. With regard to autoscaling, due to a limitation in the Cluster Autoscaler for Hetzner it is not possible yet to specify a different image for each autoscaled pool, so for now you can specify the image for all autoscaled pools by setting the `autoscaling_image` setting if you want to use an image different from the one specified in `image`.

To see the list of available images, run the following:

```bash
export API_TOKEN=...

curl -H "Authorization: Bearer $API_TOKEN" 'https://api.hetzner.cloud/v1/images?per_page=100'
```

Besides the default OS images, It's also possible to use a snapshot that you have already created from an existing server. Also with custom snapshots you'll need to specify the **ID** of the snapshot/image, not the description you gave when you created the template server.

I've tested snapshots for [openSUSE MicroOS](https://microos.opensuse.org/) but others might work too. You can easily create a snapshot for MicroOS using [this tool](https://github.com/kube-hetzner/packer-hcloud-microos). Creating the snapshot takes just a couple of minutes and then you can use it with hetzner-k3s by setting the config option `image` to the **ID** of the snapshot, and `snapshot_os` to `microos`.



### Limitations:

- if possible, please use modern SSH keys since some operating systems have deprecated old crypto based on SHA1; therefore I recommend you use ECDSA keys instead of the old RSA type
- if you use a snapshot instead of one of the default images, the creation of the servers will take longer than when using a regular image
- the setting `api_allowed_networks` allows specifying which networks can access the Kubernetes API, but this only works with single master clusters currently. Multi-master HA clusters require a load balancer for the API, but load balancers are not yet covered by Hetzner's firewalls
- if you enable autoscaling for one or more nodepools, do not change that setting afterwards as it can cause problems to the autoscaler
- autoscaling is only supported when using Ubuntu or one of the other default images, not snapshots
- worker nodes created by the autoscaler must be deleted manually from the Hetzner Console when deleting the cluster (this will be addressed in a future update)
- SSH keys with passphrases can only be used if you set `use_ssh_agent` to `true` and use an SSH agent to access your key. To start and agent e.g. on macOS:

```bash
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/<private key>
```



### Idempotency

The `create` command can be run any number of times with the same configuration without causing any issue, since the process is idempotent. This means that if for some reason the create process gets stuck or throws errors (for example if the Hetzner API is unavailable or there are timeouts etc), you can just stop the current command, and re-run it with the same configuration to continue from where it left.



### Adding nodes

To add one or more nodes to a node pool, just change the instance count in the configuration file for that node pool and re-run the create command.

**Important**: if you are increasing the size of a node pool created prior to v0.5.7, please see [this thread](https://github.com/vitobotta/hetzner-k3s/issues/80).



### Scaling down a node pool

To make a node pool smaller:

- decrease the instance count for the node pool in the configuration file so that those extra nodes are not recreated in the future
- delete the nodes from Kubernetes (`kubectl delete node <name>`)
- delete the instances from the cloud console if the Cloud Controller Manager doesn't delete it automatically (make sure you delete the correct ones 🤭)

In a future release I will add some automation for the cleanup.



### Replacing a problematic node

- delete the node from Kubernetes (`kubectl delete node <name>`)
- delete the correct instance from the cloud console
- re-run the `create` command. This will re-create the missing node and have it join to the cluster



### Converting a non-HA cluster to HA

It's easy to convert a non-HA with a single master cluster to HA with multiple masters. Just change the masters instance count and re-run the `create` command. This will create a load balancer for the API server and update the kubeconfig so that all the API requests go through the load balancer.



___
## Upgrading to a new version of k3s

If it's the first time you upgrade the cluster, all you need to do to upgrade it to a newer version of k3s is run the following command:

```bash
hetzner-k3s upgrade --config cluster_config.yaml --new-k3s-version v1.27.1-rc2+k3s1
```

So you just need to specify the new k3s version as an additional parameter and the configuration file will be updated with the new version automatically during the upgrade. To see the list of available k3s releases run the command `hetzner-k3s releases`.

Note: (single master clusters only) the API server will briefly be unavailable during the upgrade of the controlplane.

To check the upgrade progress, run `watch kubectl get nodes -owide`. You will see the masters being upgraded one per time, followed by the worker nodes.

NOTE: if you haven't used the tool in a while before upgrading, you may need to delete the file `cluster_config.yaml.example` in your temp folder to refresh the list of available k3s versions.


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



If you want to automate this process I recommend you install the [Kubernetes Reboot Daemon ](https://kured.dev/) ("Kured"). For this to work properly, make sure the OS you choose for the nodes has unattended upgrades enabled at least for security updates. For example if the image is Ubuntu, you can add this to the configuration file before running the `create` command:



```yaml
additional_packages:
- unattended-upgrades
- update-notifier-common
post_create_commands:
- sudo systemctl enable unattended-upgrades
- sudo systemctl start unattended-upgrades
```



Check the Kured documentation for configuration options like maintenance window etc.



___
## Deleting a cluster

To delete a cluster, running

```bash
hetzner-k3s delete --config cluster_config.yaml
```

This will delete all the resources in the Hetzner Cloud project created by `hetzner-k3s` directly.

**NOTE:** at the moment instances created by the cluster autoscaler, as well as load balancers and persistent volumes created by deploying your applications must be deleted manually. This may be addressed in a future release.



___
## Additional info

### Load balancers

Once the cluster is ready, you can already provision services of type LoadBalancer for your workloads (such as the Nginx ingress controller for example) thanks to the Hetzner Cloud Controller Manager that is installed automatically.

There are some annotations that you can add to your services to configure the load balancers. At a minimum your need these two:

```yaml
load-balancer.hetzner.cloud/location: nbg1 # must ensure the network location of the load balancer is same as for the nodes
load-balancer.hetzner.cloud/use-private-ip: "true" # ensures the traffic between LB and nodes goes through the private network, so you don't need to change anything in the firewall
```



The above are required, but I also recommend these:

```yaml
load-balancer.hetzner.cloud/hostname: <a valid fqdn>
load-balancer.hetzner.cloud/http-redirect-https: 'false'
load-balancer.hetzner.cloud/name: <lb name>
load-balancer.hetzner.cloud/uses-proxyprotocol: 'true'
```

I set `load-balancer.hetzner.cloud/hostname` to a valid hostname that I configure (after creating the load balancer) with the IP of the load balancer; I use this together with the annotation `load-balancer.hetzner.cloud/uses-proxyprotocol: 'true'` to enable the proxy protocol. Reason: I enable the proxy protocol on the load balancers so that my ingress controller and applications can "see" the real IP address of the client. However when this is enabled, there is a problem where [cert-manager](https://cert-manager.io/docs/) fails http01 challenges; you can find an explanation of why [here](https://github.com/compumike/hairpin-proxy) but the easy fix provided by some providers - including Hetzner - is to configure the load balancer so that it uses a hostname instead of an IP. Again, read the explanation for the reason but if you care about seeing the actual IP of the client then I recommend you use these two annotations.

The other annotations should be self explanatory. You can find a list of the available annotations [here](https://pkg.go.dev/github.com/hetznercloud/hcloud-cloud-controller-manager/internal/annotation).



**Note**: in a future release it will be possible to configure ingress controllers with host ports, so it will be possible to use an ingress without having to buy a load balancer, but for the time being a load balancer is still required.



### Persistent volumes

Once the cluster is ready you can create persistent volumes out of the box with the default storage class `hcloud-volumes`, since the Hetzner CSI driver is installed automatically. This will use Hetzner's block storage (based on Ceph so it's replicated and highly available) for your persistent volumes. Note that the minimum size of a volume is 10Gi. If you specify a smaller size for a volume, the volume will be created with a capacity of 10Gi anyway.

### Keeping a project per cluster

If you want to create multiple clusters per project, see [Configuring Cluster-CIDR and Service-CIDR](#configuring-cluster-cidr-and-service-cidr). Make sure, that every cluster has its own dedicated Cluster- and Service-CIDR. If they overlap, it will cause problems. But I still recommend keeping clusters separated from each other. This way, if you want to delete a cluster with all the resources created for it, you can just delete the project.

### Configuring Cluster-CIDR and Service-CIDR

Cluster-CIDR and Service-CIDR describe the IP-Ranges that are used for pods and services respectively. Under normal circumstances you should not need to change these values. However, advanced scenarios may require you to change them to avoid networking conflicts.

**Changing the Cluster-CIDR (Pod IP-Range):**

To change the Cluster-CIDR, uncomment/add the `cluster_cidr` option in your cluster configuration file and provide a valid CIDR notated network to use. The provided network must not be a subnet of your private network.

**Changing the Service-CIDR (Service IP-Range):**

To change the Service-CIDR, uncomment/add the `service_cidr` option in your cluster configuration file and provide a valid CIDR notated network to use. The provided network must not be a subnet of your private network.

Also uncomment the `cluster_dns` option and provide a single IP-Address from your `service_cidr` range. `cluster_dns` sets the IP-Address of the coredns service.

**Sizing the Networks**

The networks you provide should provide enough space for the expected amount of pods/services. By default `/16` networks are used. Please make sure you chose an adequate size, as changing the CIDR afterwards is not supported.



___

## Troubleshooting

If the tool hangs forever after creating servers and you see timeouts, this may be caused by problems with your SSH key, for example if you use a key with a passphrase or an older key (due to the deprecation of some crypto stuff in newwer operating systems). In this case you may want to try setting `use_ssh_agent` to `true` to use the SSH agent. If you are not familiar with what an SSH agent is, take a look at [this page](https://smallstep.com/blog/ssh-agent-explained/) for an explanation.



---
## Contributing and support

Please create a PR if you want to propose any changes, or open an issue if you are having trouble with the tool - I will do my best to help if I can.

If you would like to financially support the project, consider [becoming a sponsor](https://github.com/sponsors/vitobotta).

___
## License

This tool is available as open source under the terms of the [MIT License](https://github.com/vitobotta/hetzner-k3s/blob/main/LICENSE.txt).



___
## Code of conduct

Everyone interacting in the hetzner-k3s project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/vitobotta/hetzner-k3s/blob/main/CODE_OF_CONDUCT.md).




## Stargazers over time

[![Stargazers over time](https://starchart.cc/vitobotta/hetzner-k3s.svg)](https://starchart.cc/vitobotta/hetzner-k3s)
