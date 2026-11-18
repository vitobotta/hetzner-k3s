# Important Upgrade Notes

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
