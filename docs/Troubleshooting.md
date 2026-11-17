# Troubleshooting

This page covers common issues and their solutions. If you don't find an answer here, check [GitHub Issues](https://github.com/vitobotta/hetzner-k3s/issues) or ask in [GitHub Discussions](https://github.com/vitobotta/hetzner-k3s/discussions).

---

## Common Issues and Solutions

### SSH Connection Problems

If the tool stops working after creating instances and you experience timeouts, the issue might be related to your SSH key. This can happen if you're using a key with a passphrase or an older key, as newer operating systems may no longer support certain encryption methods.

**Solutions:**
1. **Enable SSH Agent**: Set `networking.ssh.use_agent` to `true` in your configuration file. This lets the SSH agent manage the key.
   
   For macOS:
   ```bash
   eval "$(ssh-agent -s)"
   ssh-add --apple-use-keychain ~/.ssh/<private key>
   ```

   For Linux:
   ```bash
   eval "$(ssh-agent -s)"
   ssh-add ~/.ssh/<private key>
   ```

2. **Test SSH Manually**: Verify you can SSH to the instances manually:
   ```bash
   ssh -i ~/.ssh/your_private_key root@<server_ip>
   ```

3. **Check Key Permissions**: Ensure your private key has correct permissions:
   ```bash
   chmod 600 ~/.ssh/your_private_key
   ```

### Cloud-init Script Fails with "Bad substitution"

The init scripts run under `sh` on cloud-init, which is why older versions could abort at the end of `/etc/init-0.sh` on autoscaled and newly created nodes with `sh: <n>: Bad substitution`, leaving `/etc/initialized` empty and the node half configured. The scripts are `sh` compatible now, and cloud-init invokes them with `bash` as well. Upgrading hetzner-k3s and running `create` again rewrites them.

### Enable Debug Mode

You can run `hetzner-k3s` with the `DEBUG` environment variable set to `true` for more detailed output:

```bash
DEBUG=true hetzner-k3s create --config cluster_config.yaml
```

This will provide more detailed output, which can help you identify the root of the problem.

### Create Appears to Hang on an Instance

**Symptoms**: `create` stops printing after `Instance status: running` and appears frozen.

It is waiting for the node to power on, to be attached to the private network, and to answer over SSH, retrying in between. These waits are now bounded and report what failed:

- power on: 30 attempts, then an error
- attach to the private network: 30 attempts, then an error
- SSH readiness: 20 attempts, then an error naming the last failure, for example an authentication failure rather than a silent timeout
- the whole readiness step: 20 minutes

Each SSE wait prints the elapsed time, the attempt count and the reason it is not ready yet, so a run that is merely slow looks different from one that cannot work.

**If it fails**, the message names the cause. `SSH command failed ... Permission denied` means the key is not the one on the server: check `networking.ssh` and `existing_ssh_key_name`. `no route to host` or timeouts point at the network: check `allowed_networks` and the Hetzner firewall rules. For more detail, run with `DEBUG=true`.

### Cluster Creation Fails after Node Creation

**Symptoms**: Instances are created but cluster setup fails.

**Possible Causes:**
- Network connectivity issues between nodes
- Firewall blocking communication
- Hetzner API rate limits

**Solutions:**
1. **Check Network Connectivity**: Verify nodes can communicate with each other
2. **Review Firewall Rules**: Ensure necessary ports are open
3. **Wait and Retry**: If it's a rate limit issue, wait a few minutes and retry
4. **Check Network Configuration**: See section below for IPv4/IPv6 configuration issues

### IPv4 Disabled with IPv6 Only Configuration

hetzner-k3s connects to the nodes over their public IPv6 address when public IPv4 is disabled, so SSH, the kubeconfig and the API TLS SANs use it. A connection timeout on `2a01:...` addresses means the machine running the tool has no IPv6 route; test with `ping6` or `curl -6` first. `ssh.use_private_ip: true` switches to the private network instead, which requires access to it.


**Symptoms**: Cluster creation hangs after nodes are created. SSH connection times out when trying to connect to a private IP address.

**Note**: The tool currently does not support IPv6-only public network configuration. When you disable IPv4 (`public_network.ipv4: false`) or enable `networking.ssh.use_private_ip: true`, you must run `hetzner-k3s` from a machine that has access to the same private network, either directly or through a VPN. Otherwise, the tool will attempt to use private IP addresses for SSH/API connections and fail.

### Load Balancer Issues

**Symptoms**: Load balancer stuck in "pending" state

**Solutions:**
1. **Check Annotations**: Ensure proper annotations are set on your services
2. **Verify Location**: Make sure the load balancer location matches your node locations
3. **Check DNS Configuration**: If using hostname annotation, ensure DNS is properly configured

### Node Not Ready

**Symptoms**: Nodes show up as `NotReady` status

**Solutions:**
1. **Check Node Status**:
   ```bash
   kubectl describe node <node-name>
   kubectl get nodes -o wide
   ```

2. **Check Kubelet**:
   ```bash
   ssh -i ~/.ssh/your_private_key root@<node-ip>
   systemctl status k3s-agent  # for workers
   systemctl status k3s-server  # for masters
   journalctl -u k3s-agent -f
   ```

3. **Restart K3s**:
   ```bash
   ssh -i ~/.ssh/your_private_key root@<node-ip>
   systemctl restart k3s-agent  # or k3s-server
   ```

### Pod Stuck in Pending State

**Symptoms**: Pods remain in `Pending` state indefinitely

**Solutions:**
1. **Check Resource Availability**:
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   ```
   Look for events indicating insufficient resources.

2. **Add More Nodes**: If nodes are at capacity, either scale up existing node pools or add new nodes

3. **Check Taints and Tolerations**: Ensure pods have tolerations for any node taints

### Storage Issues

**Symptoms**: PVCs stuck in `Pending` state, pods can't mount volumes

**Solutions:**
1. **Check Storage Classes**:
   ```bash
   kubectl get sc
   ```

2. **Describe PVC**:
   ```bash
   kubectl describe pvc <pvc-name> -n <namespace>
   ```

3. **Check CSI Driver**:
   ```bash
   kubectl get pods -n kube-system | grep csi
   ```

### Network Plugin Issues

**Symptoms**: Pods can't communicate with each other, DNS resolution fails

**Solutions:**
1. **Check CNI Pods**:
   ```bash
   kubectl get pods -n kube-system | grep -E '(flannel|cilium)'
   ```

2. **Restart CNI**: Restart the relevant CNI pods

### Cilium Network Validation Fails

**Symptoms**: `create` stops with `Failed Cilium network validation`

With `mode: cilium`, `create` runs a cross-node pod network check after all nodes have joined (see [Cilium MTU and network validation](Creating_a_cluster.md#cilium-mtu-and-network-validation)). The error says which step failed:

1. **Test pods did not become Ready**: the nodes could not pull the test image or start the pods. Check `kubectl -n kube-system get pods -l app.kubernetes.io/name=cilium-network-validation -o wide` while `create` is running. In air-gapped clusters or with registry mirrors, set `networking.cni.cilium.connectivity_check.image` to an image your nodes can pull. On slow links, raise `networking.cni.cilium.connectivity_check.timeout_seconds`.

2. **Small packet ping failed**: pods on different nodes cannot reach each other at all. Check the Cilium agents with `kubectl -n kube-system get pods -l k8s-app=cilium -o wide` and their logs, and check that the firewall allows traffic between nodes.

3. **Pod MTU ping failed**: small packets get through but packets as large as the pod MTU are dropped, which typically shows up as TLS handshakes or large requests that hang. Lower `networking.cni.cilium.mtu` (or `MTU` in your Helm values file) so that it fits the network path between your nodes, and set `underlay_mtu` to that path MTU so `create` validates it up front.

4. **Pod MTU larger than the configured MTU allows**: Cilium did not apply the configured MTU. Check the `mtu` key in Cilium's config with `kubectl -n kube-system get configmap cilium-config -o yaml`.

To skip the check, set `networking.cni.cilium.connectivity_check.enabled: false`.

### Upgrade Issues

**Symptoms**: Cluster upgrade process gets stuck

**Solutions:**
1. **Clean up Upgrade Resources**:
   ```bash
   kubectl -n system-upgrade delete job --all
   kubectl -n system-upgrade delete plan --all
   ```

2. **Remove Labels**:
   ```bash
   kubectl label node --all plan.upgrade.cattle.io/k3s-server- plan.upgrade.cattle.io/k3s-agent-
   ```

3. **Restart Upgrade Controller**:
   ```bash
   kubectl -n system-upgrade rollout restart deployment system-upgrade-controller
   ```

### Getting Help

If you're still experiencing issues after trying these solutions:

1. **Check GitHub Issues**: Search existing issues at [github.com/vitobotta/hetzner-k3s/issues](https://github.com/vitobotta/hetzner-k3s/issues)
2. **Create New Issue**: If your issue hasn't been reported, create a new issue with:
   - Your configuration file (redacted)
   - Full debug output (`DEBUG=true hetzner-k3s ...`)
   - Operating system and Hetzner-k3s version
   - Steps to reproduce the issue
3. **GitHub Discussions**: For general questions and discussions, use [GitHub Discussions](https://github.com/vitobotta/hetzner-k3s/discussions)

### Useful Commands for Troubleshooting

```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes
kubectl get pods -A

# Check resource usage
kubectl top nodes
kubectl top pods -A

# Check events
kubectl get events -A --sort-by='.metadata.creationTimestamp'

# Check specific pod details
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>

# Check node details
kubectl describe node <node-name>

# Check network connectivity
kubectl run test-pod --image=busybox -- sleep 3600
kubectl exec -it test-pod -- nslookup kubernetes.default
kubectl exec -it test-pod -- ping <other-pod-ip>
```
