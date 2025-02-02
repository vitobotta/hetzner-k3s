# Masters in Different Locations

You can set up a regional cluster for maximum availability by placing each master in a different European location. This means the first master will be in Falkenstein, the second in Helsinki, and the third in Nuremberg (listed in alphabetical order). This setup is only possible in network zones with multiple locations, and currently, the only such zone is `eu-central`, which includes these three European locations. For other regions, only zonal clusters are supported. Additionally, regional clusters are limited to 3 masters because we only have these three locations available.

To create a regional cluster, simply set the `instance_count` for the masters pool to 3 and specify the `locations` setting as `fsn1`, `hel1`, and `nbg1`.

## Converting a Single Master or Zonal Cluster to a Regional One

If you already have a cluster with a single master or three masters in the same European location, converting it to a regional cluster is straightforward. Just follow these steps carefully and be patient. Note that this requires hetzner-k3s version 2.2.3 or higher.

Before you begin, make sure to back up all your applications and data! This is crucial. While the migration process is relatively simple, there is always some level of risk involved.

- [ ] Set the `instance_count` for the masters pool to 3 if your cluster currently has only one master.
- [ ] Update the `locations` setting for the masters pool to include `fns1`, `hel1`, and `nbg1` like this:

```yaml
locations:
- fns1
- hel1
- nbg1
```

The locations are always processed in alphabetical order, regardless of how you list them in the `locations` property. This ensures consistency, especially when replacing a master due to node failure or other issues.

- [ ] If your cluster currently has a single master, run the `create` command with the updated configuration. This will create `master2` in Helsinki and `master3` in Nuremberg. Wait for the operation to complete and confirm that all three masters are in a ready state.
- [ ] If `master1` is not in Falkenstein (fns1):
   - Drain `master1`.
   - Delete `master1` using the command `kubectl delete node {cluster-name}-master1`.
   - Remove the `master1` instance via the Hetzner Console or the `hcloud` utility (see: https://github.com/hetznercloud/cli).
   - Run the `create` command again. This will recreate `master1` in Falkenstein.
   - SSH into each master and run the following commands to ensure `master1` has joined the cluster correctly:

```bash
sudo apt-get update
sudo apt-get install etcd-client

export ETCDCTL_API=3
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
export ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt
export ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt
export ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key

etcdctl member list
```

The last command should display something like this if everything is working properly:

```
285ab4b980c2c8c, started, test-master2-d25722af, https://10.0.0.3:2380, https://10.0.0.3:2379, false
aad3fac89b68bfb7, started, test-master1-5e550de0, https://10.0.0.4:2380, https://10.0.0.4:2379, false
c11852e25aef34e8, started, test-master3-0ed051a3, https://10.0.0.2:2380, https://10.0.0.2:2379, false
```

- [ ] If `master2` is not in Helsinki, follow the same steps as with `master1` but for `master2`. This will recreate `master2` in Helsinki.
- [ ] If `master3` is not in Nuremberg, repeat the process for `master3`. This will recreate `master3` in Nuremberg.

That’s it! You now have a regional cluster, which ensures continued operation even if one of the Hetzner locations experiences a temporary failure. I also recommend enabling the `create_load_balancer_for_the_kubernetes_api` setting to `true` if you don’t already have a load balancer for the Kubernetes API.

## Performance Considerations

This feature has been frequently requested, but I delayed implementing it until I could thoroughly test the configuration. I was concerned about latency issues, as etcd is sensitive to delays, and I wanted to ensure that the latency between the German locations and Helsinki wouldn’t cause problems.

It turns out that the default heartbeat interval for etcd is 100ms, and the latency between Helsinki and Falkenstein/Nuremberg is only 25-27ms. This means the total round-trip time (RTT) for the Raft consensus is around 60-70ms, which is well within etcd’s acceptable limits. After running benchmarks, everything works smoothly! So, there’s no need to adjust the etcd configuration for this setup.
