# Important Upgrade Notes

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
