# Upgrading a cluster created with hetzner-k3s v1.x to v2.x

The v1 version of hetzner-k3s is quite old and hasn't been supported for a while, but I know that some people haven't upgraded to v2 because until now there wasn't a straightforward process to do this.

This migration is now possible and straightforward provided you follow these instructions carefully and are patient. The migration also allows you to replace deprecated instance types (series `CX`) with new instance types.

## Prerequisites

- [ ] I recommend you install the [hcloud utility](https://github.com/hetznercloud/cli) to more easily/quickly delete old masters

## Upgrading configuration and first steps

- [ ] ==Backup apps and data==
- [ ] ==Backup kubeconfig and old config file==
- [ ] Uninstall the System Upgrade Controller
- [ ] Create resolv file on existing nodes, either manually or automate it with the `hcloud` CLI
```bash
hcloud server list | awk '{print $4}' | tail -n +2 | while read ip; do
  echo "Setting DNS for ${ip}"
  ssh -n root@${ip} "echo nameserver 8.8.8.8 | tee /etc/k8s-resolv.conf"
  ssh -n root@${ip} "cat /etc/k8s-resolv.conf"
done
```
- [ ] Convert config file to new format https://github.com/vitobotta/hetzner-k3s/releases/tag/v2.0.0
- [ ] Comment out or remove empty node pools from the config file
- [ ] Set `embedded_registry_mirror: enabled: false` if needed, depending on the current version of k3s (https://docs.k3s.io/installation/registry-mirror)
- [ ] Add `legacy_instance_type` to ==ALL== node pools, both master and workers, set to the current instance type (regardless of whether it's deprecated or not). ==This is crucial for the migration==
- [ ] Run `create` command ==with latest hetnzer-k3s using the new config file==
- [ ] Wait for all CSI pods in `kube-system` to restart, ==ensure everything is running==

## Rotating control plane instances with the new instance type

One master per time (==Switch context before rotating master1== unless your cluster has a load balancer for the Kubernetes API):

- [ ] Drain and delete the master both with kubectl and from the Hetzner console (or using the `hcloud` CLI) to also delete the actual instance
- [ ] Rerun the `create` command to recreate the master with the new instance type, wait for it to join the control plane and be in "ready" status
- [ ] SSH into each master and verify that the etcd members have been updated correctly and are in sync
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

Repeat the process for each master carefully. After the three masters have been replaced:

- [ ] Rerun the `create` command once or twice to ensure config is stable and the masters don't get restarted anymore
- [ ] [Debug DNS resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/). If there are issues with it, restart the agents for DNS resolution with the command below, then restart CoreDNS
```bash
hcloud server list | grep worker | awk '{print $4}'| while read ip; do
  echo "${ip}"
  ssh -n root@${ip} "systemctl restart k3s-agent"
  sleep 10
done
```
- [ ] Address any issues with your workloads, if any, before proceeding with the rotation of the worker nodes

## Rotating a worker node pool

- [ ] Increase node count for the pool by 1
- [ ] Run the `create` command to create the extra node required during the pool rotation

One worker node per time (apart from the last one you've just added):

- [ ] Drain a node
- [ ] Delete the drained node both with kubectl and from the Hetzner console (or using the `hcloud` CLI)
- [ ] Rerun `create` command to recreate the deleted node
- [ ] Verify that all works as expected before proceeding with the next node in the pool

Once all the existing nodes have been rotated:

- [ ] Drain the very last node in the pool which we added earlier
- [ ] Verify that all looks good
- [ ] Delete the very last node both with kubectl and from the Hetzner console (or using the `hcloud` CLI)
- [ ] Update the `instance_count` for the node pool by -1
- [ ] Proceed with the next pool

## Finalizing

- [ ] Remove the `legacy_instance_type` setting from both master and worker node pools
- [ ] Re-run the `create` command once again to double check
- [ ] Optionaly, convert the currently zonal cluster to a regional one with masters in different locations (see [this](Upgrading_a_cluster_from_1x_to_2x.md)).
