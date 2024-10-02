# Creating a cluster

The tool requires a simple configuration file in order to create/upgrade/delete clusters, in the YAML format like in the example below (commented lines are for optional settings):

```yaml
---
hetzner_token: <your token>
cluster_name: test
kubeconfig_path: "./kubeconfig"
k3s_version: v1.30.3+k3s1

networking:
  ssh:
    port: 22
    use_agent: false # set to true if your key has a passphrase
    public_key_path: "~/.ssh/id_ed25519.pub"
    private_key_path: "~/.ssh/id_ed25519"
  allowed_networks:
    ssh:
      - 0.0.0.0/0
    api: # this will firewall port 6443 on the nodes; it will NOT firewall the API load balancer
      - 0.0.0.0/0
  public_network:
    ipv4: true
    ipv6: true
  private_network:
    enabled : true
    subnet: 10.0.0.0/16
    existing_network_name: ""
  cni:
    enabled: true
    encryption: false
    mode: flannel

  # cluster_cidr: 10.244.0.0/16 # optional: a custom IPv4/IPv6 network CIDR to use for pod IPs
  # service_cidr: 10.43.0.0/16 # optional: a custom IPv4/IPv6 network CIDR to use for service IPs. Warning, if you change this, you should also change cluster_dns!
  # cluster_dns: 10.43.0.10 # optional: IPv4 Cluster IP for coredns service. Needs to be an address from the service_cidr range


# manifests:
#   cloud_controller_manager_manifest_url: "https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/v1.20.0/ccm-networks.yaml"
#   csi_driver_manifest_url: "https://raw.githubusercontent.com/hetznercloud/csi-driver/v2.9.0/deploy/kubernetes/hcloud-csi.yml"
#   system_upgrade_controller_deployment_manifest_url: "https://github.com/rancher/system-upgrade-controller/releases/download/v0.13.4/system-upgrade-controller.yaml"
#   system_upgrade_controller_crd_manifest_url: "https://github.com/rancher/system-upgrade-controller/releases/download/v0.13.4/crd.yaml"
#   cluster_autoscaler_manifest_url: "https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/hetzner/examples/cluster-autoscaler-run-on-master.yaml"

datastore:
  mode: etcd # etcd (default) or external
  external_datastore_endpoint: postgres://....

schedule_workloads_on_masters: false

# image: rocky-9 # optional: default is ubuntu-24.04
# autoscaling_image: 103908130 # optional, defaults to the `image` setting
# snapshot_os: microos # optional: specified the os type when using a custom snapshot

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
- name: medium-autoscaled
  instance_type: cpx31
  instance_count: 2
  location: fsn1
  autoscaling:
    enabled: true
    min_instances: 0
    max_instances: 3

embedded_registry_mirror:
  enabled: true

# additional_packages:
# - somepackage

# post_create_commands:
# - apt update
# - apt upgrade -y
# - apt autoremove -y

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
#timeouts:
#  instance_creation_timeout: 60 # Sometimes when you use a private network the cloud init step takes a long time so you have to increase the timeout
```

Most settings should be self explanatory; you can run `hetzner-k3s releases` to see a list of the available k3s releases.

If you don't want to specify the Hetzner token in the config file (for example if you want to use the tool with CI or want to safely commit the config file to a repository), then you can use the `HCLOUD_TOKEN` environment variable instead, which has precedence.

If you set `masters_pool.instance_count` to 1 then the tool will create a non highly available control plane; for production clusters you may want to set it to a number greater than 1. This number must be odd to avoid split brain issues with etcd and the recommended number is 3.

You can specify any number of worker node pools, static or autoscaled, and have mixed nodes with different specs for different workloads.

Hetzner cloud init settings (`additional_packages` & `post_create_commands`) can be defined in the configuration file at root level as well as for each pool if different settings are needed for different pools. If these settings are configured for a pool, these override the settings at root level.

At the moment Hetzner Cloud has five locations: two in Germany (`nbg1`, Nuremberg and `fsn1`, Falkenstein), one in Finland (`hel1`, Helsinki) and two in the USA (`ash`, Ashburn, Virginia, and `hil`, Hillsboro, Oregon). Please keep in mind that US locations only offer instances with AMD CPUs at the moment, while the newly introduced ARM instances are only available in Falkenstein-fsn1 for now.

For the available instance types and their specs, either check from inside a project when adding an instance manually or run the following with your Hetzner token:

```bash
curl -H "Authorization: Bearer $API_TOKEN" 'https://api.hetzner.cloud/v1/server_types'
```

To create the cluster run:

```bash
hetzner-k3s create --config cluster_config.yaml | tee create.log
```

This will take a few minutes depending on the number of masters and worker nodes.

### Disabling public IPs (IPv4 or IPv6 or both) on nodes

With `enable_public_net_ipv4: false` and `enable_public_net_ipv6: false` you can disable the public interface for all nodes for improved security and saving on ipv4 addresses costs. These settings are global and effects all master and worker nodes. If you disable public IPs be sure to run hetzer-k3s from a machine that has access to the same private network as the nodes either directly or via some VPN.
Additional networking setup is required via cloud init, so it's important that the machine from which you run hetzner-k3s have internet access and DNS configured correctly, otherwise the cluster creation process will get stuck after creating the nodes. See [this discussion](https://github.com/vitobotta/hetzner-k3s/discussions/252) for additional information and instructions.

### Using alternative OS images

By default, the image in use is `ubuntu-24.04` for all the nodes, but you can specify a different default image with the root level `image` config option or even different images for different static node pools by setting the `image` config option in each node pool. This way you can, for example, have some node pools with ARM instances use the correct OS image for ARM. To do this and use say Ubuntu 24.04 on ARM instances, set `image` to `103908130` with a specific image ID. With regard to autoscaling, due to a limitation in the Cluster Autoscaler for Hetzner it is not possible yet to specify a different image for each autoscaled pool, so for now you can specify the image for all autoscaled pools by setting the `autoscaling_image` setting if you want to use an image different from the one specified in `image`.

To see the list of available images, run the following:

```bash
export API_TOKEN=...

curl -H "Authorization: Bearer $API_TOKEN" 'https://api.hetzner.cloud/v1/images?per_page=100'
```

Besides the default OS images, It's also possible to use a snapshot that you have already created from an existing instance. Also with custom snapshots you'll need to specify the **ID** of the snapshot/image, not the description you gave when you created the template instance.

I've tested snapshots for [openSUSE MicroOS](https://microos.opensuse.org/) but others might work too. You can easily create a snapshot for MicroOS using [this tool](https://github.com/kube-hetzner/packer-hcloud-microos). Creating the snapshot takes just a couple of minutes and then you can use it with hetzner-k3s by setting the config option `image` to the **ID** of the snapshot, and `snapshot_os` to `microos`.


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

### Idempotency

The `create` command can be run any number of times with the same configuration without causing any issue, since the process is idempotent. This means that if for some reason the create process gets stuck or throws errors (for example if the Hetzner API is unavailable or there are timeouts etc), you can just stop the current command, and re-run it with the same configuration to continue from where it left.

Note that the kubeconfig will be overwritten when you re-run the `create` command.


### Limitations:

- if possible, please use modern SSH keys since some operating systems have deprecated old crypto based on SHA1; therefore I recommend you use ECDSA keys instead of the old RSA type
- if you use a snapshot instead of one of the default images, the creation of the instances will take longer than when using a regular image
- the setting `networking`.`allowed_networks`.`api` allows specifying which networks can access the Kubernetes API, but this only works with single master clusters currently. Multi-master HA clusters require a load balancer for the API, but load balancers are not yet covered by Hetzner's firewalls
- if you enable autoscaling for one or more nodepools, do not change that setting afterwards as it can cause problems to the autoscaler
- autoscaling is only supported when using Ubuntu or one of the other default images, not snapshots
- worker nodes created by the autoscaler must be deleted manually from the Hetzner Console when deleting the cluster (this will be addressed in a future update)
- SSH keys with passphrases can only be used if you set `networking`.`ssh`.`use_ssh_agent` to `true` and use an SSH agent to access your key. To start and agent e.g. on macOS:

```bash
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/<private key>
```

