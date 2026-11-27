# Important Upgrade Notes

## `kube_proxy_args` Reaches Worker Nodes - Friday, November 27, 2026

`kube_proxy_args` reached the masters only. It now also reaches the k3s agent on the worker nodes, where kube-proxy runs for the pods scheduled there. A cluster that does not set the key renders the same worker script as before, so the cluster autoscaler's config checksum does not change and nothing restarts.

With the key set, the next `create` re-deploys the worker script on every existing cloud worker. The unit changes, so the k3s installer restarts `k3s-agent`, and the workers are set up ten at a time, so up to ten agents restart together. Running pods keep running, but service traffic on a worker is reprogrammed by kube-proxy as its agent comes back, and a change of `proxy-mode` on a running cluster takes effect only on the nodes that restarted. Plan the run for a quiet period.

External nodes are not re-provisioned: hetzner-k3s skips the setup script on a node that is already initialized (`/etc/initialized` is `true` and `k3s-agent` is active), so such a node keeps the k3s defaults. Re-initialize the node, or add the flags by hand to the `ExecStart` of `/etc/systemd/system/k3s-agent.service`, then run `systemctl daemon-reload` and restart the unit. Autoscaled nodes get the flag when the autoscaler launches them; existing ones only with `synchronise_autoscaled_nodes: true`, five at a time.

## Placement Groups Are Opt-in and No Longer Created by Default - Saturday, November 21, 2026

Placement groups were created unconditionally until now. Hetzner rejects `POST /servers` with `invalid_input` for server types and locations that do not support them, for example `cpx31` in `ash` and `hil`, so `create` now leaves them off unless `placement_groups_enabled: true` is set.

That changes existing clusters as well. Their configuration has no key, so the next `create` stops creating groups for the nodes it adds: a new worker pool, or extra instances in an existing pool. Nodes that already exist keep the group they were created in, and `delete` still removes every group labelled with the cluster name, including the ones an older version created.

Set `placement_groups_enabled: true` to keep the previous spreading behaviour. It is the right choice for EU clusters on server types that support placement groups; leave it off for US locations.

## `create` Stops Early on a Private Network in the Wrong Zone - Saturday, November 21, 2026

The private network is looked up by name, so a network left behind by an earlier attempt in another region used to be reused silently, and Hetzner then rejected every server in the new location. `create` now compares the network's subnet zone with the zone of the masters' location and stops with a `hcloud network delete` instruction before anything else is created.

This only fires for a cluster whose configured location moved to another zone, or whose `existing_network_name` points at a network in a different zone. Such a network has no servers of its own left on it, so deleting it is safe, and the message prints the exact command. A project with a manually added subnet of an unusual type no longer breaks the network listing either.

## Cilium Clusters Run a Network Check on the Next `create` - Saturday, November 21, 2026

With `networking.cni.mode: cilium`, `create` now ends with a cross-node pod network check: two short-lived pods in `kube-system` on two Ready nodes, a small ping and a ping as large as the pod MTU with the don't-fragment bit set. It needs at least two Ready nodes and pulls `nicolaka/netshoot:v0.16` from Docker Hub on each of them.

`create` re-runs the whole installation for existing clusters, so the next `create` against a cilium cluster created with an older version runs the check too, and stops with `Failed Cilium network validation` if pods cannot carry packets of their full MTU. That is the failure the check exists to find, but it is a new failure mode for a command that used to succeed.

Air-gapped clusters and clusters that pull only through a registry mirror should point `networking.cni.cilium.connectivity_check.image` at a reachable copy, or set `connectivity_check.enabled: false` to skip the check. Clusters with a single node skip it and print a warning.

The check compares the MTU pods actually use with the size the configuration implies and stops when the two differ. Cilium's Helm chart does not restart its agents when the MTU changes, so on a cluster whose `mtu` was set or changed, run `kubectl -n kube-system rollout restart ds cilium` before `create`. Otherwise the pods still carry the previous MTU, which is a different size from the one the configuration asks for, and `create` stops with `Failed Cilium network validation`.

## gVisor Restarts k3s When It Is Enabled - Friday, November 20, 2026

`addons.gvisor` is off by default, so existing clusters are unaffected until they set it.

The runtime is installed by the node setup scripts, and the containerd template they write is read only when k3s starts. On a new cluster the installer starts k3s after the template is in place, so nothing extra happens. On a cluster that already exists, the next `create` restarts `k3s-agent` on each cloud worker whose template changed, and restarts `k3s` on a master only when `schedule_workloads_on_masters` is true, since a tainted master never runs these pods. Masters that cannot schedule workloads keep the new template for their next restart. Autoscaled nodes pick the runtime up when they launch; existing ones only with `synchronise_autoscaled_nodes`.

External nodes are not re-provisioned: hetzner-k3s skips the setup script on a node that is already initialized and prints a warning. Install runsc there by hand and restart `k3s-agent`, or re-initialize the node.

Two more things to know before turning it on: the apt install requires a Debian or Ubuntu image and stops with an error on any other image, and `version` pins the runsc build rather than following the rolling repository.

## Private API Load Balancer Restarts k3s Once - Wednesday, November 18, 2026

`disable_public_interface_for_the_kubernetes_api_load_balancer` is off by default, so existing clusters are unaffected until they set it.

Turning it on for an existing cluster switches the load balancer address in the masters' `--tls-san` from its public IP to its private IP, and workers join through that private IP. The next `create` therefore restarts k3s on the masters, the first master alone and then the others together, which on three masters is one short API outage, and restarts the k3s agent on every static worker once. Turning the setting off again (after re-enabling the public interface in the Hetzner console) restarts them the same way.

Existing autoscaled nodes are not re-rendered by `create` unless `synchronise_autoscaled_nodes` is on, so they keep joining through the load balancer's public IP, which stops answering once the setting disables it. Such a node keeps serving until its agent restarts, and then cannot rejoin. Enable `synchronise_autoscaled_nodes` so that the same `create` updates them too, or let the autoscaler replace them; nodes it launches after the change use the private IP.

With `join_via_api_server_hostname: true`, workers join through the name rather than the load balancer address, so their join address does not change and they do not restart. If the record points at the load balancer's public IP, change it to the private IP (or to the masters' private IPs) before turning the setting on, or workers cannot join.

Before turning it on, make sure the machine that runs `hetzner-k3s` can reach the private network, for example through a VPN or a bastion host: with the setting on, `create` talks to the API through the load balancer's private IP as soon as the first master is up, and so does every later command. If the existing load balancer is not attached to the cluster's private network, has no targets, or has a target that uses a public IP, `create` stops before changing anything; delete the load balancer in the Hetzner console and run `create` again to have it recreated.

## Private-only clusters require use_private_ip - Monday, November 16, 2026

A cluster with both `public_network.ipv4` and `public_network.ipv6` disabled must set `networking.ssh.use_private_ip: true`. The 2.12.0 validator already enforced this, but the private-cluster guide did not show the key. The guide now does. If an older configuration relies on the private-address fallback, add the key before running `create`; this release only makes the guide consistent with the validator, the requirement itself is unchanged.

## IPv6 Clusters Restart Their Masters Once - Sunday, November 15, 2026

A cluster with `public_network.ipv4: false` now gets a `--tls-san` for each master's IPv6 address, so the API certificate can actually be served on the address the cluster is reached at. The flag changes the `k3s server` command line, the installer writes a new unit and restarts k3s: the first master alone and then the others together, as `create` always does. On three masters that is one short API outage.

Dual-stack clusters are unaffected. Their IPv6 SAN is not rendered, so their command line stays byte for byte the same and no master restarts.

## HCLOUD_TOKEN Takes Precedence - Sunday, November 15, 2026

`HCLOUD_TOKEN` now wins over `hetzner_token` in the configuration file. Before this version the file won, so someone who exported the variable for another project and also keeps a token in this config ran against the project in the config. After upgrading, the same setup runs against the project the variable points at.

No configuration change is needed. If both are set and they differ, the tool prints one line before it does anything: `HCLOUD_TOKEN is set and differs from hetzner_token in the configuration file, using the one from HCLOUD_TOKEN`. The values themselves are never printed. An empty or whitespace-only variable still counts as unset and the file is used.

## OpenSSH Upgrade Notice - Friday, August 1, 2025

### Critical Information

Due to a recent OpenSSH upgrade made available for Ubuntu, there is a significant risk that cluster nodes created with a version of hetzner-k3s prior to 2.3.4 might become unreachable via SSH once OpenSSH gets upgraded and the nodes are rebooted.

### The Problem

The OpenSSH upgrade changes systemd socket configuration behavior, which can cause SSH connectivity issues if the socket configuration file `/etc/systemd/system/ssh.socket.d/listen.conf` is not properly configured to handle IPv6 binding.

### Solution for Reachable Nodes

If the nodes in your cluster are still reachable via SSH, you can fix this issue by running the following command:

```bash
hetzner-k3s run --config <your-config-file> --script fix-ssh.sh
```

This command will automatically fix the contents of `/etc/systemd/system/ssh.socket.d/listen.conf` to ensure SSH connectivity continues working after the OpenSSH server upgrade.

The script is available at the root of this project's repository and will:
- Create a backup of the original configuration file with a timestamp
- Properly configure the socket file to handle both IPv4 and IPv6 connections
- Preserve all existing `ListenStream` configurations
- Restart the SSH socket to apply changes

### Workaround for Unreachable Nodes

If your nodes are no longer reachable via SSH due to OpenSSH already having been upgraded, there is a manual workaround available:

1. Run the `kube-shell` script from the project's repository (in the `bin` directory)
2. Specify the name of a node to fix as the first and only argument
3. This will open an SSH-like session on the node via `kubectl` using a temporary privileged pod
4. Within this session, manually modify `/etc/systemd/system/ssh.socket.d/listen.conf` to append the line:
   ```
   BindIPv6Only=default
   ```

**Important:** This manual method must be performed for each node individually Exercise caution when modifying system configuration files.

### Affected Versions

- **Fixed in**: hetzner-k3s 2.3.5 and later
- **Affected**: All versions prior to 2.3.5

### Recommendation

We strongly recommend upgrading to hetzner-k3s 2.3.5 or later and running the fix script proactively before any OpenSSH upgrades occur to prevent any connectivity issues.

### Additional Resources

For more information about SSH configuration and troubleshooting, please refer to the [Troubleshooting](Troubleshooting.md) documentation.
