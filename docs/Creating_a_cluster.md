# Creating a Cluster

This page covers the full configuration reference for hetzner-k3s. For a quick start, see the [Quick Start in the README](https://github.com/vitobotta/hetzner-k3s#quick-start) or the [Complete Tutorial](Setting_up_a_cluster.md).

---

## Configuration File

hetzner-k3s uses a YAML configuration file. Below is a complete example with all options. Commented lines are optional:

```yaml
---
hetzner_token: <your token>
cluster_name: test
kubeconfig_path: "./kubeconfig"
k3s_version: v1.32.0+k3s1
config_format_version: 1

networking:
  ssh:
    port: 22
    use_agent: false # set to true if your key has a passphrase
    use_private_ip: false # set to true to connect to nodes via their private IPs
    public_key_path: "~/.ssh/id_ed25519.pub"
    private_key_path: "~/.ssh/id_ed25519"
    # existing_ssh_key_name: "my-existing-key" # optional: use an existing SSH key in Hetzner instead of creating a new one
  # tailscale: # optional: private admin access to nodes and the Kubernetes API via a Tailscale tailnet, see https://github.com/vitobotta/hetzner-k3s/blob/main/docs/Tailscale_integration.md
  #   enabled: false
  #   hostname_suffix: "my-tailnet.ts.net" # required when enabled
  #   auth_key: "tskey-auth-..." # optional: defaults to the TAILSCALE_AUTH_KEY environment variable
  #   version: "1.80.2" # optional: pin the Tailscale package version installed on each node
  allowed_networks:
    ssh:
      - 0.0.0.0/0
    api: # this will firewall port 6443 on the nodes
      - 0.0.0.0/0
    # OPTIONAL: define extra inbound/outbound firewall rules.
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
    # custom_firewall_rules:
    #   - description: "Allow HTTP from any IPv4"
    #     direction: in
    #     protocol: tcp
    #     port: 80
    #     source_ips:
    #       - 0.0.0.0/0
    #   - description: "UDP game servers (outbound)"
    #     direction: out
    #     protocol: udp
    #     port: 60000-60100
    #     destination_ips:
    #       - 203.0.113.0/24
  # node_port_firewall_enabled: true # optional: set false to disable NodePort firewall rules (TCP/UDP)
  # node_port_range: "30000-32767" # optional: NodePort range to open on firewalls (TCP/UDP)
  public_network:
    ipv4: true
    ipv6: true
    # hetzner_ips_query_server_url: https://.. # for large clusters, see https://github.com/vitobotta/hetzner-k3s/blob/main/docs/Recommendations.md
    # hetzner_ips_token: "" # optional read-only token for the local firewall, see the recommendations page
    # use_local_firewall: false # for large clusters, see https://github.com/vitobotta/hetzner-k3s/blob/main/docs/Recommendations.md
    # use_hetzner_firewall: true # Hetzner Cloud firewall, attached by label selector. Set false to create none.
  private_network:
    enabled: true
    subnet: 10.0.0.0/16
    existing_network_name: ""
    external_routing: false # set true if external nodes can reach the private network through your own VPN/routing
  cni:
    enabled: true
    encryption: false
    mode: flannel
    cilium:
      # Optional: specify a path to a custom values file for Cilium Helm chart
      # When specified, this file will be used instead of the default values
      # helm_values_path: "./cilium-values.yaml"
      # chart_version: "v1.17.2"
      # hubble_enabled: true # set false to drop Hubble; relay and ui then follow unless set
      # hubble_relay_enabled: true
      # hubble_ui_enabled: true

  # cluster_cidr: 10.244.0.0/16 # optional: a custom IPv4/IPv6 network CIDR to use for pod IPs
  # service_cidr: 10.43.0.0/16 # optional: a custom IPv4/IPv6 network CIDR to use for service IPs. Warning, if you change this, you should also change cluster_dns!
  # cluster_dns: 10.43.0.10 # optional: IPv4 Cluster IP for coredns service. Needs to be an address from the service_cidr range
  # cluster_domain: cluster.local # optional: custom cluster domain

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

schedule_workloads_on_masters: false # set to true to allow pods to be scheduled on master nodes (useful for small clusters)

# image: rocky-9 # optional: default is ubuntu-24.04
# autoscaling_image: 103908130 # optional, defaults to the `image` setting
# snapshot_os: microos # optional: specified the os type when using a custom snapshot

masters_pool:
  instance_type: cpx22
  instance_count: 3 # for HA; you can also create a single master cluster for dev and testing (not recommended for production)
  locations: # You can choose a single location for single master clusters or if you prefer to have all masters in the same location. For regional clusters (which are only available in the eu-central network zone), each master needs to be placed in a separate location.
    - fsn1
    - hel1
    - nbg1

worker_node_pools:
- name: small-static
  instance_type: cpx22
  instance_count: 4
  location: hel1
  # image: debian-11
  # labels: # Kubernetes labels to apply to nodes in this pool (for node selection in workloads)
  #   - key: purpose
  #     value: blah
  # taints: # Kubernetes taints to apply to nodes in this pool (to repel pods unless they tolerate the taint)
  #   - key: something
  #     value: value1:NoSchedule
- name: medium-autoscaled
  instance_type: cpx32
  location: fsn1
  autoscaling:
    enabled: true
    min_instances: 0
    max_instances: 3

# addons:
#   coredns:
#     enabled: false # let hetzner-k3s manage CoreDNS instead of k3s (default false). See "Customizing CoreDNS" below.
#     replicas: 1
#     image: "rancher/mirrored-coredns-coredns:1.12.0"
#     resources:
#       requests:
#         cpu: 100m
#         memory: 70Mi
#       limits:
#         memory: 170Mi
#   csi_driver:
#     enabled: true   # Hetzner CSI driver (default true). Set to false to skip installation.
#     manifest_url: "https://raw.githubusercontent.com/hetznercloud/csi-driver/v2.21.2/deploy/kubernetes/hcloud-csi.yml"
#   traefik:
#     enabled: false  # built-in Traefik ingress controller. Disabled by default.
#   servicelb:
#     enabled: false  # built-in ServiceLB. Disabled by default.
#   metrics_server:
#     enabled: false  # Kubernetes metrics-server addon. Disabled by default.
#   local_path_storage_class:
#     enabled: false  # k3s built-in local-path provisioner (default false). See "Non-default local-path storage class" below.
#     default: true   # mark local-path as the cluster default storage class (default true).
#   cluster_autoscaler:
#     enabled: true # Cluster Autoscaler addon (default true). Set to false to omit autoscaling.
#     # manifest_url: "https://example.com/cluster-autoscaler.yaml" # optional: fetch a manifest instead of using the bundled one
#     # local_manifest_path: "./cluster-autoscaler.yaml" # optional: read a manifest from disk instead of fetching it or using the bundled one
#     container_image_tag: "v1.35.0"
#     scan_interval: "10s"                        # How often cluster is reevaluated for scale up or down
#     scale_down_delay_after_add: "10m"           # How long after scale up that scale down evaluation resumes
#     scale_down_delay_after_delete: "10s"        # How long after node deletion that scale down evaluation resumes
#     scale_down_delay_after_failure: "3m"        # How long after scale down failure that scale down evaluation resumes
#     max_node_provision_time: "15m"              # Maximum time CA waits for node to be provisioned
#     # new_pod_scale_up_delay: "0s"              # How old an unschedulable pod must be before scale up considers it
#   cloud_controller_manager:
#     enabled: true   # Hetzner Cloud Controller Manager (default true). Disabling stops automatic LB provisioning for Service objects.
#     manifest_url: "https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/v1.33.0/ccm-networks.yaml"
#   system_upgrade_controller:
#     enabled: true   # System Upgrade Controller (default true). Set to false to omit autoscaling.
#     deployment_manifest_url: "https://github.com/rancher/system-upgrade-controller/releases/download/v0.19.2/system-upgrade-controller.yaml"
#     crd_manifest_url: "https://github.com/rancher/system-upgrade-controller/releases/download/v0.19.2/crd.yaml"
#   embedded_registry_mirror:
#     enabled: false # Enables fast p2p distribution of container images between nodes for faster pod startup. Check if your k3s version is compatible before enabling this option. You can find more information at https://docs.k3s.io/installation/registry-mirror
#   gvisor:
#     enabled: false # Adds the gVisor (runsc) container runtime next to runc and a "gvisor" RuntimeClass. Debian and Ubuntu images only. See "Sandboxed workloads with gVisor" below.
#     version: "20261116.0" # runsc build installed from the gVisor apt repository. Pinned on purpose; the repository itself is rolling.

protect_against_deletion: true # prevents accidental deletion of the cluster with the "hetzner-k3s delete" command

synchronise_autoscaled_nodes: false # also bring existing nodes of autoscaling pools up to date on create; see below
reconcile_node_pools: false # also remove worker nodes that the configuration no longer renders; see below

create_load_balancer_for_the_kubernetes_api: false # creates a load balancer for HA API access, which workers also join through; note: Hetzner firewalls can't yet restrict access to load balancers by IP

disable_public_interface_for_the_kubernetes_api_load_balancer: false # makes the API load balancer reachable only via the private network; see Limitations below

k3s_upgrade_concurrency: 1 # how many nodes to upgrade at the same time; increase for faster upgrades in large clusters, but higher values may impact availability

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
# join_via_api_server_hostname: false # optional: workers join through api_server_hostname instead of the API load balancer or the first master's IP (see below). Requires the name to resolve on the nodes (DNS or root-level additional_pre_k3s_commands).
```

Most settings are straightforward and easy to understand. To see a list of available k3s releases, you can run the command `hetzner-k3s releases`.

If you prefer not to include the Hetzner token directly in the config file—perhaps for use with CI or to safely commit the config to a repository—you can use the `HCLOUD_TOKEN` environment variable instead. This variable takes precedence over the config file: while it is set and not blank, whatever `hetzner_token` contains is ignored, so a placeholder in a committed config is fine. An empty or whitespace-only value counts as unset. If both hold a token and the two differ, `create` prints one line saying that the variable is the one in use, so a token exported for another project does not go unnoticed.

### Skipping the Hetzner Cloud firewall

Two different firewalls exist and they are independent:

- `use_hetzner_firewall` (default `true`) is Hetzner's own cloud firewall. The tool creates one per cluster, names it after the cluster, attaches it to every server through the label `cluster=<name>`, and passes the name to the autoscaler so new nodes get it too.
- `use_local_firewall` (default `false`) is the nftables script the tool installs inside the nodes instead.

Hetzner limits firewalls and rules per project and recommends them only for servers with public IP addresses, which matters when you run many clusters or many nodes that only have private IPs. Setting `use_hetzner_firewall: false` creates and updates nothing, omits the autoscaler variable, and deletes a firewall left over from an earlier run:

```yaml
networking:
  public_network:
    use_hetzner_firewall: false
```

With both settings off the nodes have no filtering at all, so anything reachable on a public address is open. Combine it with `use_local_firewall: true` if you want filtering without consuming the Hetzner quota. `delete` removes a firewall if one still exists.

### IPv6 instead of a public IPv4

With `networking.public_network.ipv4: false` and `ipv6: true` the nodes get no public IPv4, and `create` still has to reach them. Unless `ssh.use_private_ip` is set, the tool connects to the public address and prefers IPv6 when there is no IPv4, for the kubeconfig, the API TLS SANs and the load balancer address as well. The machine running hetzner-k3s therefore needs working IPv6 connectivity.

```yaml
networking:
  public_network:
    ipv4: false
    ipv6: true
```

Turning both families off is rejected unless a private network is enabled and `ssh.use_private_ip` is set.

### Rotating the Hetzner API token

The Hetzner components read the token from the `hcloud` secret when their pods start, so after a rotation the running pods keep the old one. The Cloud Controller Manager then fails to authenticate and new nodes stay tainted `node.cloudprovider.kubernetes.io/uninitialized`.

Running `create` again with the new token fixes that: when the token in the secret differs from the configured one, hetzner-k3s updates the secret and rolls the deployments and the DaemonSet that consume it, then waits for them. Nothing restarts while the token is unchanged, so ordinary runs stay quiet, and no instances are recreated. Resource changes are applied only after the restarted pods are ready, which is a few seconds for each component.

A rollout that does not finish within three minutes is logged and the run continues, because the cluster itself is fine and the pods can be inspected afterwards.

### SSH keys from environment variables

The cluster SSH key pair can come from the environment too, so an unattended run such as a CI job does not have to write key files first:

```bash
export SSH_PRIVATE_KEY="$(cat ~/.ssh/id_ed25519)"
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
hetzner-k3s create --config cluster_config.yaml
```

`SSH_PRIVATE_KEY`, or `SSH_PUBLIC_KEY` alone when the private half comes from `existing_ssh_key_name` or from a running ssh agent. Both take precedence over `private_key_path` and `public_key_path`. The content is written to `~/.hetzner-k3s/ssh` with a name derived from it and permissions of 0600, so repeated runs reuse the same files, and everything that works on a path, including the fingerprint comparison against Hetzner, uses those files. When only the private key is set, the public key is derived with `ssh-keygen`. Escaped `\n` sequences, surrounding indentation and a missing trailing newline are handled.

`use_agent: true` together with `SSH_PRIVATE_KEY` fails validation, because with an agent the key path is never passed to ssh: drop one of the two.

The materialised files stay in `~/.hetzner-k3s/ssh` and can be deleted at any time; the next run writes them again.

External node pools are unaffected, since their `ssh_private_key_path` is configured per node.

When setting `masters_pool`.`instance_count`, keep in mind that if you set it to 1, the tool will create a control plane that is not highly available. For production clusters, it's better to set this to a number greater than 1. To avoid split brain issues with etcd, this number should be odd, and 3 is the recommended value. Additionally, for production environments, it's a good idea to configure masters in different locations using the `masters_pool`.`locations` setting.

The `datastore` section configures how Kubernetes stores its cluster state. The default mode is `etcd`, which runs an embedded etcd cluster on your master nodes—this is the recommended option for most deployments. For very large clusters or special requirements, you can use `external` mode with an external datastore (etcd, PostgreSQL, or MySQL) by specifying the connection string in `external_datastore_endpoint`. The etcd mode also supports optional S3 backup configuration for disaster recovery.

You can define any number of worker node pools, either static or autoscaled, and create pools with nodes of different specifications to handle various workloads. Every pool needs a unique `name`: pool names may only contain lowercase letters, digits and dashes, and must start with a letter, because the name is used to build the names of the Hetzner Cloud servers in the pool. Each pool can have optional `labels` and `taints`. Labels are key-value pairs that help you target specific nodes when scheduling workloads using node selectors or affinity rules. Taints prevent pods from being scheduled on certain nodes unless the pods explicitly tolerate the taint—useful for dedicating nodes to specific workloads or keeping certain nodes free for particular purposes.

Settings, such as `additional_packages`, `additional_pre_k3s_commands`, and `additional_post_k3s_commands`, can be specified at the root level of the configuration file or for each individual pool if different settings are needed. If these settings are configured at the pool level, they will override any settings defined at the root level.

- `additional_pre_k3s_commands`: Commands executed before k3s installation
- `additional_post_k3s_commands`: Commands executed after k3s is installed and configured

For an example of using `additional_post_k3s_commands` to resize the root partition for use with storage solutions like Rook Ceph, see [Resizing root partition with additional post k3s commands](./Resizing_root_partition_with_post_create_commands.md).

The `addons` section controls which components hetzner-k3s installs automatically:

- **csi_driver**: The Hetzner CSI driver enables persistent volumes backed by Hetzner block storage. Enabled by default; disable if you're using alternative storage solutions like Rook Ceph or Longhorn.
- **cloud_controller_manager**: Integrates with Hetzner Cloud to provision load balancers automatically when you create Kubernetes Service objects of type LoadBalancer. Enabled by default.
- **system_upgrade_controller**: Enables zero-downtime rolling upgrades of k3s across your cluster. Enabled by default.
- **cluster_autoscaler**: Automatically scales worker node pools based on resource demands. Enabled by default when you have autoscaling pools defined.
- **coredns**: CoreDNS is shipped and managed by k3s by default. Set `addons.coredns.enabled: true` to have hetzner-k3s deploy and own it instead, which makes `replicas`, `image` and container resources configurable. See [Customizing CoreDNS](#customizing-coredns).
- **traefik**: k3s's built-in ingress controller. Disabled by default; enable if you want a quick ingress solution without installing your own.
- **servicelb**: k3s's built-in load balancer for bare-metal environments. Disabled by default; typically not needed when using Hetzner's load balancers.
- **metrics_server**: Enables `kubectl top` commands for viewing resource usage. Disabled by default.
- **embedded_registry_mirror**: Enables peer-to-peer distribution of container images between nodes for faster pod startup. Disabled by default; check k3s version compatibility before enabling.
- **gvisor**: Installs the gVisor (runsc) container runtime next to runc and creates a `gvisor` RuntimeClass, so selected pods can run under a user-space kernel. Debian and Ubuntu images only. Disabled by default, because only pods that ask for it use it. See [Sandboxed workloads with gVisor](#sandboxed-workloads-with-gvisor).

### Customizing CoreDNS

CoreDNS is a component that k3s packages and re-applies on every start, so its manifest, and with it the resource limits, cannot be edited in place: the edits are reverted the next time k3s starts. hetzner-k3s therefore leaves CoreDNS to k3s unless you opt in. With `addons.coredns.enabled: true` it starts k3s with `--disable coredns` and deploys its own copy of the manifest, which it then keeps in sync on every `create`:

```yaml
addons:
  coredns:
    enabled: true
    replicas: 2
    resources:
      requests:
        cpu: 100m
        memory: 100Mi
      limits:
        memory: 512Mi
```

`replicas` defaults to 1 while the toggle is on, and `resources` falls back to the k3s values (limits 170Mi memory, requests 100m cpu and 70Mi memory) for anything you leave out. k3s sets no cpu limit and neither does the fallback, so add one with `resources.limits.cpu` if you want a ceiling. `image` defaults to the CoreDNS image the k3s release this version targets, which means that after a k3s upgrade the pinned image stays until you change it here or bump hetzner-k3s.

Point to keep in mind:

- Switching the toggle on replaces the deployment. k3s uninstalls its packaged CoreDNS when it starts with the flag, so expect a DNS outage of roughly the length of the run between the k3s restart and the addon installation, one to three minutes. Nothing else restarts, in-cluster name resolution is what fails, and a node-local DNS cache only stretches the first 30 seconds. Pods keep running and long-lived connections keep working.
- The managed deployment keeps the k3s object names and the `k8s-app: kube-dns` label, and the `kube-dns` Service keeps its ClusterIP from `cluster_dns`. That matters if you run a node-local DNS cache, which forwards to the Service, and for the resolver configuration of every pod.
- Switching the toggle off, or removing the block, hands CoreDNS back: the k3s defaults are applied immediately, the ownership label is removed, and k3s owns the deployment again from its next restart. The rollout uses `maxSurge: 1` and `maxUnavailable: 0`, so a replica stays available unless the cluster has no room for the surge pod.
- While the toggle is on the config is authoritative, so a manual `kubectl scale` or `kubectl edit` is reset on the next `create`. With the toggle off, `replicas` is only reconciled when you set it, so a manual scale stays in place unless the field is present in the config. `replicas` is the only setting that applies in both modes.

### Sandboxed workloads with gVisor

gVisor adds a second container runtime to every node: pods that ask for it run under a user-space kernel instead of the host kernel, which shrinks what a compromised workload can reach. hetzner-k3s installs `runsc` next to containerd, registers it as a runtime, and creates a cluster-scoped RuntimeClass:

```yaml
addons:
  gvisor:
    enabled: true
    # version: "20261116.0" # runsc build from the gVisor apt repository
```

Workloads opt in individually:

```yaml
spec:
  runtimeClassName: gvisor
```

Pods that leave `runtimeClassName` unset keep using runc, so the rest of the cluster runs as before.

Points to keep in mind:

- **Debian and Ubuntu images only.** `runsc` comes from the `.deb` the gVisor project publishes, and there is no RPM. Setup stops with an error on any other image instead of finishing without the runtime. External node pools already require a Debian-based OS.
- **`version` pins the build.** The gVisor apt repository has a single rolling component, so an unpinned install would upgrade `runsc` on every node at every `create`. Bump `version` when you want a newer build.
- **It costs disk and memory on every node.** The package is about 87 MB compressed and roughly 250 MB installed, and every sandboxed pod keeps a second kernel in memory.
- **Enabling it on an existing cluster restarts k3s.** The containerd template is read only when k3s starts. `create` compares the template and restarts `k3s-agent` on each cloud worker whose file changed, and restarts `k3s` on a master only when `schedule_workloads_on_masters` is true, since a tainted master never runs these pods. Nodes without a change are left alone. Autoscaled nodes pick the runtime up when they launch; existing ones only with `synchronise_autoscaled_nodes`.
- **External node pools are not re-provisioned.** hetzner-k3s skips the setup script once an external node is initialized, and prints a warning saying runsc is missing there. Install it by hand or re-initialize the node:

```bash
apt-get update && apt-get install -y apt-transport-https ca-certificates curl gnupg
curl -fsSL https://gvisor.dev/archive.key | gpg --batch --yes --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" | tee /etc/apt/sources.list.d/gvisor.list > /dev/null
apt-get update && apt-get install -y "runsc=20261116.0"
```

Then add the runtime to the containerd template and restart the agent:

```toml
# /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
{{ template "base" . }}

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
```

```bash
systemctl restart k3s-agent
```

- **Some workloads do not work under it.** gVisor implements a subset of the Linux API. GPU access, `hostNetwork` tricks and some security tooling are unsupported, so try a workload under the RuntimeClass before moving production traffic to it.

### Cluster Autoscaler on Kubernetes 1.35 and later

Since Kubernetes 1.35 the autoscaler ships dynamic resource allocation enabled and locked on, so it always lists and watches `deviceclasses`, `resourceslices` and `resourceclaims`. The example manifests do not grant that yet (kubernetes/autoscaler#9487), which fills the pod log with `cannot list resource "resourceslices" in API group "resource.k8s.io"` errors.

hetzner-k3s adds the missing rule to the autoscaler ClusterRole itself, for the bundled manifest and for one fetched through `manifest_url` or `local_manifest_path`, so nothing is needed on your side. A rule already present in a manifest is left as it is.

Note that the autoscaler image has to match the cluster's Kubernetes minor version. If you run 1.35, set `addons.cluster_autoscaler.container_image_tag` to the matching `v1.35.x`.

### Cluster Autoscaler manifest

hetzner-k3s ships the autoscaler manifest with the binary, taken from `kubernetes/autoscaler` at the release matching the default image tag, instead of following the upstream `master` branch. Upstream changes therefore cannot break a run, and the `imagePullSecrets: gitlab-registry` entry the upstream example carries is dropped: the image is public and the secret never existed, which made kubelet emit a warning event on every pull attempt.

`manifest_url` and `local_manifest_path` still replace it wholesale. Whatever you supply is patched the same way, so keep the `cluster-autoscaler` container name and the `ssl-certs` volume name.

### Non-default local-path storage class

k3s installs `local-path` as a default StorageClass, and its packaged manifest is re-applied on every start, so removing the `storageclass.kubernetes.io/is-default-class` annotation by hand does not survive a restart. To keep the class but let another one, `hcloud-volumes` for example, stay the only default:

```yaml
addons:
  local_path_storage_class:
    enabled: true
    default: false
```

`enabled: true` keeps k3s from passing `--disable local-storage`, so the provisioner is installed as usual, and `default: false` makes hetzner-k3s overwrite the annotation right after the installer stops running k3s. The annotation is set again on every `create`, which is what keeps it correct across restarts and the k3s manifest apply. `default: true` is the current behaviour and needs no patch.

With `enabled: false` the storage class is not installed at all, so `default: false` without `enabled: true` fails validation.

The patch runs on the first master and waits up to a minute for the class to appear; if the flag is written back after the patch it retries once and then aborts the run.

The `api_server_hostname` setting is useful when you enable `create_load_balancer_for_the_kubernetes_api`. After the cluster is created, you can point this DNS name to the API load balancer's address, giving you a stable hostname for accessing the Kubernetes API. With `join_via_api_server_hostname` (below), workers also join through it.

Workers register with the cluster (the `K3S_URL` their `k3s-agent` bootstraps from) through one of three addresses:

- No API load balancer, `join_via_api_server_hostname` off: the first master.
- `create_load_balancer_for_the_kubernetes_api` enabled (and more than one master), `join_via_api_server_hostname` off: the load balancer.
- `join_via_api_server_hostname: true` with `api_server_hostname` set: the name, whether or not there is a load balancer.

External nodes always join through the first master. Through the load balancer or the name, a node, static or autoscaled, can still join while the first master is down.

With the load balancer, workers use the same load balancer address as the kubeconfig, because that is the address in the masters' certificates: the private one with `networking.ssh.use_private_ip: true` or `disable_public_interface_for_the_kubernetes_api_load_balancer: true`, the public one otherwise.

That address is what the agent bootstraps from, not where its traffic normally goes. Once a worker has joined, `k3s-agent` fetches the list of API servers from the supervisor (the masters' advertised addresses, their private IPs on a cluster with a private network) and load-balances across them; the `K3S_URL` server is kept only as a fallback for when none of them answers. So steady-state traffic from workers to the control plane stays on the private network whatever `use_private_ip` is set to. With the default `use_private_ip: false` the join itself, and the fallback, go to the load balancer's public IP; `use_private_ip: true` moves both to its private IP, which the masters' certificates already carry in that mode. Using the private IP without `use_private_ip` means adding it to the certificates, which restarts every master on an existing cluster, so it is not done automatically: `disable_public_interface_for_the_kubernetes_api_load_balancer: true` is the opt-in for it, and also removes the public address (see the Limitations below).

On a cluster created with an earlier version, the next `create` restarts `k3s-agent` once on each static worker (up to ten in parallel; running pods keep running); existing autoscaled nodes keep the old address and new ones use the load balancer, unless `synchronise_autoscaled_nodes` is enabled: then the next `create` updates the existing ones too, five at a time.

#### Joining through `api_server_hostname`

`join_via_api_server_hostname: true` makes workers join through `api_server_hostname`. It is what lets a cluster without an API load balancer survive the first master being down: point the name at all masters, for example with one A record per master's private IP. The agent tries the addresses in turn until one answers, paying a connect timeout on each dead one. On a cluster with a load balancer the setting adds less, since workers already join through it; it is only useful there if you want the name, rather than the load balancer address, in `K3S_URL`. If that cluster also sets `disable_public_interface_for_the_kubernetes_api_load_balancer`, the name must resolve to a private address (the load balancer's private IP, or the masters' private IPs): the name wins over the load balancer address, and a record that still points at the load balancer's public IP leaves workers unable to join.

With the flag on, the name decides the path: whatever it resolves to is what workers connect to, so `networking.ssh.use_private_ip` no longer governs the join. As above, this only affects the join and the fallback; steady-state traffic still goes to the masters' advertised addresses.

The name must already resolve on the nodes when the setting takes effect, through DNS or through the root-level `additional_pre_k3s_commands` (for example lines appended to `/etc/hosts`). A pool-level `additional_pre_k3s_commands` is not enough for autoscaled pools: static workers run the pool's commands, but the cluster autoscaler's cloud-init carries only the root-level ones, so autoscaled nodes would never resolve the name and never join. If the name points at the API load balancer, whose address only exists after the first `create`, create the cluster first, add the DNS record, then enable the setting and run `create` again. With the default `synchronise_autoscaled_nodes: false`, existing autoscaled nodes keep the address they joined with and only new ones use the hostname. With it on, the next `create` updates the existing nodes too, five at a time, and restarts `k3s-agent` where the address changed.

Enabling it on a running cluster restarts nodes, so do it in a quiet window:

- **Static workers.** The next `create` points every static worker's `k3s-agent` at the name and restarts it once. Workers are updated in parallel, up to ten at a time, not one by one. Restarting `k3s-agent` does not stop running containers, so pods are not evicted, but each node's kubelet is briefly unavailable while it reconnects. A name that does not resolve leaves those workers unable to reach the API.
- **Masters, if `api_server_hostname` is new as well.** `create` runs the install script on every master each time, and the k3s installer restarts `k3s` only when its unit or environment changed. Adding the name changes the masters' TLS SANs, so this time `k3s` restarts on every master: the first master on its own, then all the other masters at the same time. On a three-master cluster with the embedded etcd datastore that takes two of the three members down together, so expect the Kubernetes API to be unavailable until they are back. Adding `api_server_hostname` in one `create` and `join_via_api_server_hostname` in a later one only separates the two restarts. If the name is already set, the masters are not restarted.

Currently, Hetzner Cloud offers six locations: two in Germany (`nbg1` in Nuremberg and `fsn1` in Falkenstein), one in Finland (`hel1` in Helsinki), two in the USA (`ash` in Ashburn, Virginia and `hil` in Hillsboro, Oregon), and one in Singapore (`sin`). Be aware that not all instance types are available in every location, so it’s a good idea to check the Hetzner site and their status page for details.

To explore the available instance types and their specifications, you can either check them manually when adding an instance within a project or run the following command with your Hetzner token:

```bash
curl -H "Authorization: Bearer $API_TOKEN" 'https://api.hetzner.cloud/v1/server_types'
```

To create the cluster run:

```bash
hetzner-k3s create --config cluster_config.yaml | tee create.log
```

If you need to bypass the validation that your current IP is included in the allowed SSH/API networks, add `--skip-current-ip-validation`.

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
  instance_type: cpx32
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
  instance_type: cpx32
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

- **`new_pod_scale_up_delay`**: How long a pod must exist as unschedulable before the autoscaler considers it for a scale up. Useful with bursting or batch workloads, where pods sit pending for a moment while the scheduler shuffles them onto existing nodes and a scale up would add capacity that is not needed. Individual pods can override it with the `cluster-autoscaler.kubernetes.io/pod-scale-up-delay` annotation.
  - *Default*: `0s`, and the flag is left out of the deployment entirely so the autoscaler default applies

All six values are durations in the Go form, so `45s`, `1.5m` or `1h30m` are all valid. A value without a unit (`45`) or an unknown unit is rejected when the configuration is validated, rather than crash-looping the autoscaler later.

These settings apply globally to all autoscaling worker node pools in your cluster.

Anything the settings above do not cover can be passed straight to the autoscaler with the top-level `cluster_autoscaler_args` list, which is appended to the command verbatim:

```yaml
cluster_autoscaler_args:
- "--skip-nodes-with-local-storage=false"
```

A flag in `cluster_autoscaler_args` that duplicates a setting is passed twice; the setting comes later, so it wins.

---

### External Node Pools

External node pools let you attach worker nodes from **any provider** (not just Hetzner Cloud) to your cluster. You provision and own these nodes; hetzner-k3s performs the same setup steps that cloud-init would on a Hetzner node (firewall, packages, k3s install) but via SSH instead.

#### Configuration

An external node pool uses `instance_type: external` and defines its nodes in the `external` section:

```yaml
worker_node_pools:
- name: external-workers
  instance_type: external
  instance_count: 2
  external:
    provider: generic
    nodes:
      - host: 203.0.113.10
        ssh_user: root
        ssh_port: 22
        ssh_private_key_path: ~/.ssh/external_node_key
        manage_hostname: true
        index: 1
      - host: 198.51.100.20
        ssh_user: ubuntu
        ssh_port: 2222
        ssh_private_key_path: ~/.ssh/external_node_key
        manage_hostname: true
        index: 2
```

For Hetzner Robot dedicated servers, use `provider: robot` at the pool level:

```yaml
worker_node_pools:
- name: robot-workers
  instance_type: external
  instance_count: 2
  external:
    provider: robot
    robot_user: your-robot-webservice-user
    robot_password: your-robot-webservice-password
    nodes:
      - host: 203.0.113.30
        robot_server_number: 123456
        ssh_user: root
        ssh_private_key_path: ~/.ssh/robot_node_key
        manage_hostname: true
        index: 1
      - host: 203.0.113.31
        robot_server_number: 123457
        ssh_user: root
        ssh_private_key_path: ~/.ssh/robot_node_key
        manage_hostname: true
        index: 2
```

If `robot_user` and `robot_password` are omitted, hetzner-k3s reads them from `ROBOT_USER` and `ROBOT_PASSWORD`.

Robot credentials are Robot Webservice credentials, created in the Robot UI under **Settings** -> **Web service and app settings**.

#### External provider modes

| Provider | Description |
|---|---|
| `generic` | Default. Use for external nodes from any provider, including Robot servers that should behave as unmanaged external workers. hetzner-k3s does not ask the Hetzner Cloud Controller Manager to initialize these nodes. |
| `robot` | Use for Hetzner Robot dedicated servers that should be known to the Hetzner Cloud Controller Manager as Robot nodes. Requires Robot Webservice credentials and `robot_server_number` for every node. |

#### Node properties

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| `host` | String | yes | — | SSH endpoint of the external node (must be a valid IPv4 address, not a DNS hostname) |
| `ip` | String | no | `host` | Node's locally assigned, cluster-reachable IPv4 address in externally routed private-network mode. Set this when the SSH endpoint differs from the node's routed address. Only supported with `private_network.enabled: true` and `private_network.external_routing: true`. |
| `ssh_user` | String | yes | — | SSH username for the node (e.g. `root`, `ubuntu`) |
| `ssh_port` | Int32 | no | `22` | SSH port |
| `ssh_private_key_path` | String | yes | — | Path to the SSH private key (supports `~/` expansion) |
| `manage_hostname` | Bool | no | `true` | If true, hetzner-k3s sets the node's hostname to match its naming convention |
| `index` | Int32 | yes | — | 1-based slot index; ties a node config to a specific hostname slot |
| `robot_server_number` | Int32 | yes for `provider: robot` | — | Robot server number used for the `hrobot://` provider ID and Robot API lookups |

#### The `index` field

The `index` property ties a node config entry to a specific hostname slot. When `manage_hostname: true`, the hostname is derived from the index (not the array position), so reordering the `nodes` array does not change hostnames. Indices must be:

- **Unique** within a pool (no duplicates)
- **In the range `1..instance_count`**

For example, if `instance_count: 3`, valid indices are `1`, `2`, `3`. The `instance_count` must equal the number of nodes in `external.nodes`.

#### Requirements

External nodes must:

- Run a **Debian-based OS** (Debian or Ubuntu). Package installation uses `apt-get`. No other package managers (dnf, zypper, pacman) are supported.
- Be accessible via SSH from the machine running hetzner-k3s, using the specified private key and user.
- Have **root access** — either the SSH user is `root`, or the user has **passwordless sudo**.

#### Required cluster settings

External node pools require the following cluster-wide settings:

- `networking.private_network.enabled: false` and `networking.public_network.use_local_firewall: true` — external nodes use the public network and the local firewall is deployed to each external node via SSH.
- Or `networking.private_network.enabled: true` and `networking.private_network.external_routing: true` — external nodes use your own VPN/routing connectivity to reach the private network.
- `networking.public_network.hetzner_ips_query_server_url` must be set when using the public-network/local-firewall mode (required by the local firewall to fetch Hetzner node IPs).
- `networking.public_network.hetzner_ips_token`, when set, must not be empty.

#### Externally routed private networks

Use `external_routing: true` when you already provide routing (for example, a site-to-site VPN) between external workers and the Hetzner private network. Hetzner cloud masters and workers continue to use their normal private-network interface and address, including when they also have public IPs. The flag only changes address selection for external workers; it does not create a VPN or install routes.

For each external worker, `ip` defaults to `host`. This preserves private-IP-only configurations. When SSH uses a different address, configure both explicitly:

```yaml
networking:
  private_network:
    enabled: true
    subnet: 10.20.0.0/16
    external_routing: true
worker_node_pools:
  - name: routed-workers
    instance_type: external
    instance_count: 1
    external:
      provider: generic
      nodes:
        - host: 192.0.2.10 # SSH endpoint
          ip: 10.10.0.10 # Address assigned to the worker and reachable by the cluster
          ssh_user: root
          ssh_private_key_path: ~/.ssh/external-worker
          manage_hostname: false
          index: 1
```

The worker registers with `--node-ip=ip`. If `host` differs, it is also advertised as `--node-external-ip=host`; otherwise that redundant flag is omitted. Neither address is guessed from the order of `hostname -I`. The cluster IP must be assigned to an interface on the worker; installation fails with an explanatory error otherwise. Flannel uses that interface, including on multihomed hosts. Generic workers use `external://<cluster-ip>` as their provider ID in this mode; Robot workers retain `hrobot://<server-number>` and their existing HCCM/Robot requirements.

You are responsible for the routed network and its firewall rules:

- All participating node addresses must have bidirectional reachability, including cloud-to-external and external-to-external traffic. SSH reachability from the installer alone is insufficient. Avoid overlapping node, pod, service and VPN address ranges.
- Allow workers to reach the Kubernetes API on masters (TCP 6443), and the control plane to reach worker kubelets (TCP 10250). Permit any additional ports required by your enabled features.
- Permit the selected CNI transport between nodes: Flannel VXLAN and Cilium VXLAN normally use UDP 8472; Cilium Geneve uses UDP 6081. Encryption changes the requirements (for example, Flannel WireGuard IPv4 UDP 51820 and Cilium WireGuard UDP 51871). Check the documentation for your configured CNI/version and IPv6 settings.
- With an encapsulated CNI, the underlay must route the node/tunnel-endpoint addresses; it does not need direct routes for every pod CIDR. Native/direct-routing configurations also require bidirectional pod-CIDR routing between the external nodes and the cloud network.
- Account for VPN plus CNI encapsulation overhead when configuring MTU, and permit any ICMP/health traffic required for path-MTU discovery and CNI health checks.
- **hetzner-k3s does not deploy its managed local firewall in private-network mode**, even if `use_local_firewall` is set. Supply the required protection on your routers and/or nodes. The public-network IP-query service is not required in routing mode.

Node addresses and interface flags are set at installation time. Changing `external_routing`, `host` or `ip` does not migrate an installed node: `create` skips k3s installation on initialized external workers. Plan a controlled drain and node recreation/reinstallation when changing these settings. Updating the CLI alone does not rewrite existing nodes. Do not switch an existing cluster between public and private addressing by simply toggling this flag.

#### Validation rules

The following rules are enforced at config validation time:

1. Private network must be disabled unless `networking.private_network.external_routing` is enabled.
2. Local firewall must be enabled when external nodes use the public network.
3. No Hetzner-specific fields allowed in the pool (`image`, `autoscaling`, `grow_root_partition_automatically`, `legacy_instance_type`).
4. Masters pool cannot use `instance_type: external`.
5. `instance_count` must equal the number of nodes in `external.nodes`.
6. Node indices must be unique and in range `1..instance_count`.
7. Node hosts must be unique within a pool.
8. Robot pools must define Robot credentials and `robot_server_number` for every node.
9. Robot server numbers must be unique across Robot external pools.
10. `external_routing: true` requires private networking to be enabled and at least one external worker pool.
11. In routing mode, effective cluster IPs (`ip`, or `host` if omitted) must be valid IPv4 addresses and unique across external pools. An explicit `ip` is rejected outside routing mode.

At runtime, before cluster creation begins, hetzner-k3s also validates:

- **SSH accessibility** — can it connect to each node?
- **Root/sudo access** — does the SSH user have root or passwordless sudo?
- **Hostname conflicts** — if `manage_hostname: false`, does the existing hostname conflict with any hostname hetzner-k3s will generate?
- **Robot metadata** — for `provider: robot`, `host` must match the Robot server IP returned for `robot_server_number`. If `manage_hostname: false`, the Robot server name must be a valid Kubernetes node name and must match the node's OS hostname.

#### Setup behavior

When you run `hetzner-k3s create`, for each external node hetzner-k3s will:

1. Set the hostname (if `manage_hostname: true`).
2. Install packages (`fail2ban`, `wireguard`, plus any `additional_packages`).
3. Configure the DNS resolver.
4. In public-network/local-firewall mode, deploy the local firewall (rendered with the node's own SSH port). This step is skipped in externally routed private-network mode.
5. Run pre-k3s commands (`additional_pre_k3s_commands`).
6. Install k3s worker and join it to the cluster.
7. Run post-k3s commands (`additional_post_k3s_commands`).

To reinstall an external worker in place, drain it, stop k3s on it with `k3s-killall.sh` (which keeps the node's data, unlike `k3s-agent-uninstall.sh`) and run `create` again: the stopped agent sends the node through the full install path. If the regenerated k3s service is identical to the previous one, the k3s installer skips its own service start; the install script then starts the agent itself.

With `provider: generic`, external workers are not initialized by the Hetzner Cloud Controller Manager. hetzner-k3s installs them without kubelet's `cloud-provider=external` argument, and assigns a synthetic `external://<public-ip>` provider ID (or `external://<cluster-ip>` in externally routed mode) so the cloud node lifecycle controller will not delete them when they are temporarily NotReady.

With `provider: robot`, hetzner-k3s installs workers with kubelet's `cloud-provider=external` argument and assigns `hrobot://<server-number>` provider IDs. It also enables Robot support in the Hetzner Cloud Controller Manager manifest and adds the Robot credentials to the `hcloud` secret. If `manage_hostname: true`, hetzner-k3s updates the Robot server name through the Robot Webservice API before setting the OS hostname. If `manage_hostname: false`, the existing Robot server name and OS hostname must already match.

Robot nodes can be used as Hetzner Load Balancer IP targets through the Hetzner Cloud Controller Manager. Public-IP targets work with Robot API credentials. Private-IP targets require a Robot vSwitch/InternalIP setup and service annotation `load-balancer.hetzner.cloud/use-private-ip: "true"`.

External nodes are labeled with `hetzner-k3s.io/external=true` and `hetzner-k3s.io/external-provider=<provider>`. The Hetzner CSI node driver is configured not to run on external nodes, because Hetzner Cloud Volumes can be attached only to Hetzner Cloud servers. When external pools are present, hetzner-k3s also sets the CSI controller's default volume location to the first master location so the controller does not depend on the Hetzner metadata service. Keep workloads that use the `hcloud-volumes` StorageClass on Hetzner Cloud nodes, or use a storage backend that supports your external nodes.

The `hetzner-k3s delete` command will clean up external nodes by uninstalling k3s, removing firewall files, and resetting iptables/ip6tables policies to accept traffic again via SSH.

#### `hetzner-k3s run` support

The `run` command detects external nodes by matching their IP against the `external.nodes[].host` entries, or their effective cluster IP in externally routed mode. It can also match generated names when `manage_hostname: true`. If a match is found, it connects to the configured `host` using the node's per-node SSH settings (key, user, port), even when the Kubernetes InternalIP differs. This allows you to run commands and scripts on external nodes just like on Hetzner nodes.

---
### Reconciling node pools

`create` only ever adds. Removing a pool from the configuration, or lowering an `instance_count`, leaves the old nodes running until you drain and delete them by hand. `reconcile_node_pools: true` closes that gap: after the normal flow, `create` drains and deletes workers that the configuration no longer renders, so the file can be the source of truth.

It is opt-in and destructive, so it asks first:

- with a terminal, it lists the nodes and waits for a `y`
- `--dry-run` lists them and stops
- `--force` applies without asking, which is what CI needs, since there is no terminal there. Without a terminal and without `--force` nothing is removed and the nodes are only listed.

What it will not touch: masters (the expected set contains them even though `create` does not reconcile master counts), autoscaled nodes, which the autoscaler labels with `hcloud/node-group` on the server (the node object carries no such label, so they are looked up per autoscaling pool and matched by name prefix), external nodes of pools that are still in the configuration, and anything the configuration still renders. A node that does not manage its hostname reports the machine's own hostname, so a node with no server of this cluster that is not named like one of its workers is left alone as well, even after its pool is removed. Note that renaming a pool therefore replaces all of its nodes, since every old name drops out of the expected set.

Each node is cordoned first, then drained with `--ignore-daemonsets --delete-emptydir-data --timeout=10m`, then its instance is deleted. If a drain fails or times out, the instance is kept, the remaining nodes are still processed, and the run ends non-zero, so a later `create` finishes the job. An external node of a pool you removed is drained and removed from the cluster like any other, but nothing is deleted through the Hetzner API.

Two things to watch for: a PodDisruptionBudget that cannot be satisfied blocks the drain until the timeout expires, and pods using `local-path` storage come back empty on another node because the volume is pinned to the node being removed.

### Updating autoscaled nodes

`create` provisions only the pools that are not autoscaling. Nodes created later by the Cluster Autoscaler therefore keep the configuration they were born with: changes to `private_registry_config`, kubelet args, labels or taints never reach them, and a rotated registry credential or a changed mirror silently stops image pulls on those nodes.

Set `synchronise_autoscaled_nodes: true` to let `create` reach them too. It is off by default because it opens a new class of remote work: `create` connects to nodes the autoscaler owns.

What happens on a run:

- only instances of pools with `autoscaling.enabled`, found by their `hcloud/node-group` server label, are considered;
- nodes that are not `Ready` yet, and nodes the autoscaler has cordoned for a scale down, are skipped;
- five nodes are updated at a time, so a large pool does not restart all at once;
- a node that disappears mid-run (scale down) is reported and never aborts the run, and the closing line counts updated, skipped and failed nodes.

**A node whose configuration did not change is not restarted.** Before writing `registries.yaml` the worker script compares it with the file on the node. An identical file is left alone and needs no restart, because k3s reads that file only at startup. Unit and flag changes are already handled by the k3s installer, which restarts the agent itself when the unit changes, and by nothing at all when it does not. This is also why the first `create` with a new version of hetzner-k3s causes no restart wave on a cluster that is already in sync: there is no hash or marker file to be missing, the comparison is against the node's own files.

Two consequences worth knowing:

- a change is applied on the node at the moment it is written, and the restart follows immediately in the same run, so a run can only be interrupted between the two by killing it. Re-running `create` fixes that node.
- if you edit `/etc/rancher/k3s/registries.yaml` by hand and the rendered content is the same, the hand edit is reverted on the next run without a restart, since the restart side of it is driven by the file having changed.

### Idempotency

The `create` command can be run multiple times with the same configuration without causing issues, as the process is idempotent. If the process gets stuck or encounters errors (e.g., due to Hetzner API unavailability or timeouts), you can stop the command and rerun it with the same configuration to continue where it left off. Note that the kubeconfig will be overwritten each time you rerun the command.

---

### Limitations:

- Using a snapshot instead of a default image will take longer to create instances compared to regular images.
- The `networking`.`allowed_networks`.`api` setting specifies which networks can access the Kubernetes API. This works with both single-master and multi-master clusters, but only when `create_load_balancer_for_the_kubernetes_api` is disabled. If the API load balancer is enabled, Hetzner's firewalls do not yet support load balancers, so the API would be exposed to the public internet regardless of the allowed networks configuration. To keep the API load balancer off the public internet, set `disable_public_interface_for_the_kubernetes_api_load_balancer` to `true`, which makes the load balancer reachable only via the private network. With it on:
    - The master nodes themselves still expose the API on their public IPs, as controlled by `networking`.`allowed_networks`.`api`, so restrict that list as well (or disable the public network interface on the nodes) if the API must not be reachable from the public internet at all.
    - kubectl and every hetzner-k3s command, including the `create` that first applies the setting, must be run from a machine that can reach the private network, for example via a VPN or a bastion host: as soon as the first master is up, `create` talks to the API through the load balancer's private IP.
    - Turning the setting on or off for an existing cluster changes the load balancer address in the API server certificate, so the next `create` restarts k3s on the masters (the first master alone, then the others together, which on three masters means one short API outage) and the k3s agent on every static worker, which picks up the new join address. Existing autoscaled nodes keep the old address unless `synchronise_autoscaled_nodes` is enabled, or until the autoscaler replaces them; nodes it launches afterwards use the new one. See the [upgrade notes](Important_upgrade_notes.md).
    - If an existing load balancer is not attached to the private network, or any of its targets uses a public IP, `create` stops before changing anything. Delete the load balancer in the Hetzner console and run `create` again, so that it is recreated attached to the network with private targets.
    - Disabling the setting again does not re-enable the public interface of an existing load balancer; re-enable it manually in the Hetzner console and then run `create` again, so that the kubeconfig and the API server certificate use the public IP address.
- If you enable autoscaling for a nodepool, avoid changing this setting later, as it can cause issues with the autoscaler.
- Autoscaling is only supported with Ubuntu or other default images, not snapshots.
- If you already have SSH keys in your Hetzner project, it's best to use a different key for your cluster—unless there's already a key with the same name and fingerprint as the one in your config file.  Hetzner doesn't allow two keys with the same fingerprint in one project. So if you've already added the key from your config but under a different name, Hetzner won't let you add it again. In that case, hetzner-k3s will skip creating the key and won't inject any SSH key into the cluster nodes.  Without an SSH key, Hetzner sets up the nodes with password login instead. That means you'll get an email for each node with its root password. Managing several nodes this way can get tricky. To avoid this, you can either use a new keypair for your cluster, or set `existing_ssh_key_name` in the SSH config to reference the existing key by name. When using `existing_ssh_key_name`, hetzner-k3s will use the specified key instead of creating a new one, and it won't delete the key when you delete the cluster.
- SSH keys with passphrases can only be used if you set `networking`.`ssh`.`use_ssh_agent` to `true` and use an SSH agent to access your key. For example, on macOS, you can start an agent like this:

```bash
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/<private key>
```
