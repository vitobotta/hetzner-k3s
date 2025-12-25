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

### Enable Debug Mode

You can run `hetzner-k3s` with the `DEBUG` environment variable set to `true` for more detailed output:

```bash
DEBUG=true hetzner-k3s create --config cluster_config.yaml
```

This will provide more detailed output, which can help you identify the root of the problem.

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

**Symptoms**: Cluster creation hangs after nodes are created. SSH connection times out when trying to connect to a private IP address.

**Note**: The tool currently does not support IPv6-only public network configuration. When you disable IPv4 (`public_network.ipv4: false`), you must run `hetzner-k3s` from a machine that has access to the same private network, either directly or through a VPN. Otherwise, the tool will attempt to use the private IP addresses for SSH connections and fail.

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
