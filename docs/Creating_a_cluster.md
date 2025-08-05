# Creating a cluster

The tool needs a basic configuration file, written in YAML format, to handle tasks like creating, upgrading, or deleting clusters. Below is an example where commented lines indicate optional settings:

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
    api: # this will firewall port 6443 on the nodes
      - 0.0.0.0/0
    # OPTIONAL: define extra inbound firewall rules.
    # Each entry supports the following keys:
    #   description (string, optional)
    #   direction   (in | out, default: in)
    #   protocol    (tcp | udp | icmp | esp | gre, default: tcp)
    #   port        (single port "80", port range "30000-32767", or "any") – only relevant for tcp/udp
    #   source_ips  (array of CIDR blocks) – required when direction is in
    #   destination_ips (array of CIDR blocks) – required when direction is out
    #
    # IMPORTANT: Outbound traffic is allowed by default (implicit allow-all).
    # If you add **any** outbound rule (direction: out), Hetzner Cloud switches
    # the outbound chain to an implicit **deny-all**; only traffic matching your
    # outbound rules will be permitted. Define outbound rules carefully to avoid
    # accidentally blocking required egress (DNS, updates, etc.).
    # NOTE: Hetzner Cloud Firewalls support **max 50 entries per firewall**. The built-
    # in rules (SSH, ICMP, node-port ranges, etc.) use ~10 slots. If the sum of the
    # default rules plus your custom ones exceeds 50, hetzner-k3s will abort with
    # an error.
    custom:
      - description: "Allow HTTP from any IPv4"
        protocol: tcp
        direction: in
        port: 80
        source_ips:
          - 0.0.0.0/0
      - description: "UDP game servers (outbound)"
        direction: out
        protocol: udp
        port: 60000-60100
        destination_ips:
          - 203.0.113.0/24
  public_network:
    ipv4: true
    ipv6: true
    # hetzner_ips_query_server_url: https://.. # for large clusters, see https://github.com/vitobotta/hetzner-k3s/blob/main/docs/Recommendations.md
    # use_local_firewall: false # for large clusters, see https://github.com/vitobotta/hetzner-k3s/blob/main/docs/Recommendations.md
  private_network:
    enabled: true
    subnet: 10.0.0.0/16
    existing_network_name: ""
  cni:
    enabled: true
    encryption: false
    mode: flannel
    cilium:
      # Optional: specify a path to a custom values file for Cilium Helm chart
      # When specified, this file will be used instead of the default values
      # helm_values_path: "./cilium-values.yaml"
      # chart_version: "v1.17.2"

  # cluster_cidr: 10.244.0.0/16 # optional: a custom IPv4/IPv6 network CIDR to use for pod IPs
  # service_cidr: 10.43.0.0/16 # optional: a custom IPv4/IPv6 network CIDR to use for service IPs. Warning, if you change this, you should also change cluster_dns!
  # cluster_dns: 10.43.0.10 # optional: IPv4 Cluster IP for coredns service. Needs to be an address from the service_cidr range


# manifests:
#   cloud_controller_manager_manifest_url: "https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/v1.23.0/ccm-networks.yaml"
#   csi_driver_manifest_url: "https://raw.githubusercontent.com/hetznercloud/csi-driver/v2.12.0/deploy/kubernetes/hcloud-csi.yml"
#   system_upgrade_controller_deployment_manifest_url: "https://github.com/rancher/system-upgrade-controller/releases/download/v0.14.2/system-upgrade-controller.yaml"
#   system_upgrade_controller_crd_manifest_url: "https://github.com/rancher/system-upgrade-controller/releases/download/v0.14.2/crd.yaml"
#   cluster_autoscaler_manifest_url: "https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/hetzner/examples/cluster-autoscaler-run-on-master.yaml"
#   cluster_autoscaler_container_image_tag: "v1.32.0"

datastore:
  mode: etcd # etcd (default) or external
  external_datastore_endpoint: postgres://....
#  etcd:
#    # etcd snapshot configuration (optional)
#    snapshot_retention: 24
#    snapshot_schedule_cron: "0 * * * *"
#
#    # S3 snapshot configuration (optional)
#    s3_enabled: false
#    s3_endpoint: "" # Can also be set with ETCD_S3_ENDPOINT environment variable
#    s3_region: "" # Can also be set with ETCD_S3_REGION environment variable
#    s3_bucket: "" # Can also be set with ETCD_S3_BUCKET environment variable
#    s3_access_key: "" # Can also be set with ETCD_S3_ACCESS_KEY environment variable
#    s3_secret_key: "" # Can also be set with ETCD_S3_SECRET_KEY environment variable
#    s3_folder: ""
#    s3_force_path_style: false

schedule_workloads_on_masters: false

# image: rocky-9 # optional: default is ubuntu-24.04
# autoscaling_image: 103908130 # optional, defaults to the `image` setting
# snapshot_os: microos # optional: specified the os type when using a custom snapshot

masters_pool:
  instance_type: cpx21
  instance_count: 3 # for HA; you can also create a single master cluster for dev and testing (not recommended for production)
  locations: # You can choose a single location for single master clusters or if you prefer to have all masters in the same location. For regional clusters (which are only available in the eu-central network zone), each master needs to be placed in a separate location.
    - fsn1
    - hel1
    - nbg1

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
  location: fsn1
  autoscaling:
    enabled: true
    min_instances: 0
    max_instances: 3

# cluster_autoscaler:
#   scan_interval: "10s"                        # How often cluster is reevaluated for scale up or down
#   scale_down_delay_after_add: "10m"           # How long after scale up that scale down evaluation resumes
#   scale_down_delay_after_delete: "10s"        # How long after node deletion that scale down evaluation resumes
#   scale_down_delay_after_failure: "3m"        # How long after scale down failure that scale down evaluation resumes
#   max_node_provision_time: "15m"              # Maximum time CA waits for node to be provisioned

embedded_registry_mirror:
  enabled: false # Enables fast p2p distribution of container images between nodes for faster pod startup. Check if your k3s version is compatible before enabling this option. You can find more information at https://docs.k3s.io/installation/registry-mirror

# addons:
#   csi_driver:
#     enabled: true   # Hetzner CSI driver (default true). Set to false to skip installation.
#   traefik:
#     enabled: false  # built-in Traefik ingress controller. Disabled by default.
#   servicelb:
#     enabled: false  # built-in ServiceLB. Disabled by default.
#   metrics_server:
#     enabled: false  # Kubernetes metrics-server addon. Disabled by default.
#   cloud_controller_manager:
#     enabled: true   # Hetzner Cloud Controller Manager (default true). Disabling stops automatic LB provisioning for Service objects.
#   cluster_autoscaler:
#     enabled: true   # Cluster Autoscaler addon (default true). Set to false to omit autoscaling.

protect_against_deletion: true

create_load_balancer_for_the_kubernetes_api: false # Just a heads up: right now, we can’t limit access to the load balancer by IP through the firewall. This feature hasn’t been added by Hetzner yet.

k3s_upgrade_concurrency: 1 # how many nodes to upgrade at the same time

# additional_packages:
# - somepackage

# additional_pre_k3s_commands:
# - apt update
# - apt upgrade -y

# additional_post_k3s_commands:
# - apt autoremove -y
# For more advanced usage like resizing the root partition for use with Rook Ceph, see [Resizing root partition with additional post k3s commands](./Resizing_root_partition_with_post_create_commands.md)

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

Most settings are straightforward and easy to understand. To see a list of available k3s releases, you can run the command `hetzner-k3s releases`.

If you prefer not to include the Hetzner token directly in the config file—perhaps for use with CI or to safely commit the config to a repository—you can use the `HCLOUD_TOKEN` environment variable instead. This variable takes precedence over the config file.

When setting `masters_pool`.`instance_count`, keep in mind that if you set it to 1, the tool will create a control plane that is not highly available. For production clusters, it’s better to set this to a number greater than 1. To avoid split brain issues with etcd, this number should be odd, and 3 is the recommended value. Additionally, for production environments, it’s a good idea to configure masters in different locations using the `masters_pool`.`locations` setting.

You can define any number of worker node pools, either static or autoscaled, and create pools with nodes of different specifications to handle various workloads.

Hetzner Cloud init settings, such as `additional_packages`, `additional_pre_k3s_commands`, and `additional_post_k3s_commands`, can be specified at the root level of the configuration file or for each individual pool if different settings are needed. If these settings are configured at the pool level, they will override any settings defined at the root level.

- `additional_pre_k3s_commands`: Commands executed before k3s installation
- `additional_post_k3s_commands`: Commands executed after k3s is installed and configured

For an example of using `additional_post_k3s_commands` to resize the root partition for use with storage solutions like Rook Ceph, see [Resizing root partition with additional post k3s commands](./Resizing_root_partition_with_post_create_commands.md).

Currently, Hetzner Cloud offers six locations: two in Germany (`nbg1` in Nuremberg and `fsn1` in Falkenstein), one in Finland (`hel1` in Helsinki), two in the USA (`ash` in Ashburn, Virginia and `hil` in Hillsboro, Oregon), and one in Singapore (`sin`). Be aware that not all instance types are available in every location, so it’s a good idea to check the Hetzner site and their status page for details.

To explore the available instance types and their specifications, you can either check them manually when adding an instance within a project or run the following command with your Hetzner token:

```bash
curl -H "Authorization: Bearer $API_TOKEN" 'https://api.hetzner.cloud/v1/server_types'
```

To create the cluster run:

```bash
hetzner-k3s create --config cluster_config.yaml | tee create.log
```

This process will take a few minutes, depending on how many master and worker nodes you have.

### Disabling public IPs (IPv4 or IPv6 or both) on nodes

To improve security and save on IPv4 address costs, you can disable the public interface for all nodes by setting `enable_public_net_ipv4: false` and `enable_public_net_ipv6: false`. These settings are global and will apply to all master and worker nodes. If you disable public IPs, make sure to run hetzner-k3s from a machine that has access to the same private network as the nodes, either directly or through a VPN.

Additional networking setup is required via cloud-init, so it’s important that the machine you use to run hetzner-k3s has internet access and DNS configured correctly. Otherwise, the cluster creation process will get stuck after creating the nodes. For more details and instructions, you can refer to [this discussion](https://github.com/vitobotta/hetzner-k3s/discussions/252).

### Using alternative OS images

By default, the image used for all nodes is `ubuntu-24.04`, but you can specify a different default image by using the root-level `image` config option. You can also set different images for different static node pools by using the `image` config option within each node pool. For example, if you have node pools with ARM instances, you can specify the correct OS image for ARM. To do this, set `image` to `103908130` with the specific image ID.

However, for autoscaling, there’s a current limitation in the Cluster Autoscaler for Hetzner. You can’t specify different images for each autoscaled pool yet. For now, if you want to use a different image for all autoscaling pools, you can set the `autoscaling_image` option to override the default `image` setting.

To see the list of available images, run the following:

```bash
export API_TOKEN=...

curl -H "Authorization: Bearer $API_TOKEN" 'https://api.hetzner.cloud/v1/images?per_page=100'
```

Besides the default OS images, you can also use a snapshot created from an existing instance. When using custom snapshots, make sure to specify the **ID** of the snapshot or image, not the description you assigned when creating the template instance.

I’ve tested snapshots with [openSUSE MicroOS](https://microos.opensuse.org/), but other options might work as well. You can easily create a MicroOS snapshot using [this Terraform-based tool](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/blob/master/packer-template/hcloud-microos-snapshots.pkr.hcl). The process only takes a few minutes. Once the snapshot is ready, you can use it with hetzner-k3s by setting the `image` configuration option to the **ID** of the snapshot and `snapshot_os` to `microos`.

---

### Keeping a Project per Cluster

If you plan to create multiple clusters within the same project, refer to the section on [Configuring Cluster-CIDR and Service-CIDR](#configuring-cluster-cidr-and-service-cidr). Ensure that each cluster has its own unique Cluster-CIDR and Service-CIDR. Overlapping ranges will cause issues. However, I still recommend separating clusters into different projects. This makes it easier to clean up resources—if you want to delete a cluster, simply delete the entire project.

---

### Configuring Cluster-CIDR and Service-CIDR

Cluster-CIDR and Service-CIDR define the IP ranges used for pods and services, respectively. In most cases, you won’t need to change these values. However, advanced setups might require adjustments to avoid network conflicts.

**Changing the Cluster-CIDR (Pod IP Range):**
To modify the Cluster-CIDR, uncomment or add the `cluster_cidr` option in your cluster configuration file and specify a valid CIDR notation for the network. Make sure this network is not a subnet of your private network.

**Changing the Service-CIDR (Service IP Range):**
To adjust the Service-CIDR, uncomment or add the `service_cidr` option in your configuration file and provide a valid CIDR notation. Again, ensure this network is not a subnet of your private network. Also, uncomment the `cluster_dns` option and provide a single IP address from the `service_cidr` range. This sets the IP address for the coredns service.

**Sizing the Networks:**
The networks you choose should have enough space for your expected number of pods and services. By default, `/16` networks are used. Select an appropriate size, as changing the CIDR later is not supported.

---

### Autoscaler Configuration

The cluster autoscaler automatically manages the number of worker nodes in your cluster based on resource demands. When you enable autoscaling for a worker node pool, you can also configure various timing parameters to fine-tune its behavior.

#### Basic Autoscaling Configuration

```yaml
worker_node_pools:
- name: autoscaled-pool
  instance_type: cpx31
  location: fsn1
  autoscaling:
    enabled: true
    min_instances: 1
    max_instances: 10
```

#### Advanced Timing Configuration

You can customize the autoscaler's behavior with these optional parameters at the root level of your configuration:

```yaml
cluster_autoscaler:
  scan_interval: "2m"                      # How often cluster is reevaluated for scale up or down
  scale_down_delay_after_add: "10m"        # How long after scale up that scale down evaluation resumes
  scale_down_delay_after_delete: "10s"     # How long after node deletion that scale down evaluation resumes
  scale_down_delay_after_failure: "15m"    # How long after scale down failure that scale down evaluation resumes
  max_node_provision_time: "15m"           # Maximum time CA waits for node to be provisioned

worker_node_pools:
- name: autoscaled-pool
  instance_type: cpx31
  location: fsn1
  autoscaling:
    enabled: true
    min_instances: 1
    max_instances: 10
```

#### Parameter Descriptions

- **`scan_interval`**: Controls how frequently the cluster autoscaler evaluates whether scaling is needed. Shorter intervals mean faster response to load changes but more API calls.
  - *Default*: `10s`

- **`scale_down_delay_after_add`**: Prevents the autoscaler from immediately scaling down after adding nodes. This helps avoid thrashing when workloads are still starting up.
  - *Default*: `10m`

- **`scale_down_delay_after_delete`**: Adds a delay before considering more scale-down operations after a node deletion. This ensures the cluster stabilizes before further changes.
  - *Default*: `10s`

- **`scale_down_delay_after_failure`**: When a scale-down operation fails, this parameter controls how long to wait before attempting another scale-down.
  - *Default*: `3m`

- **`max_node_provision_time`**: Sets the maximum time the autoscaler will wait for a new node to become ready. This is particularly useful for clusters with private networks where provisioning might take longer.
  - *Default*: `15m`

These settings apply globally to all autoscaling worker node pools in your cluster.

---

### Idempotency

The `create` command can be run multiple times with the same configuration without causing issues, as the process is idempotent. If the process gets stuck or encounters errors (e.g., due to Hetzner API unavailability or timeouts), you can stop the command and rerun it with the same configuration to continue where it left off. Note that the kubeconfig will be overwritten each time you rerun the command.

---

### Limitations:

- Using a snapshot instead of a default image will take longer to create instances compared to regular images.
- The `networking`.`allowed_networks`.`api` setting specifies which networks can access the Kubernetes API, but this currently only works with single-master clusters. Multi-master HA clusters can optionally use a load balancer for the API, but Hetzner’s firewalls do not yet support load balancers.
- If you enable autoscaling for a nodepool, avoid changing this setting later, as it can cause issues with the autoscaler.
- Autoscaling is only supported with Ubuntu or other default images, not snapshots.
- SSH keys with passphrases can only be used if you set `networking`.`ssh`.`use_ssh_agent` to `true` and use an SSH agent to access your key. For example, on macOS, you can start an agent like this:

```bash
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/<private key>
```

