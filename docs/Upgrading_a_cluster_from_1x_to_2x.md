# Upgrading a cluster created with hetzner-k3s v1.x to v2.x

The v1 version of hetzner-k3s is quite old and hasn’t been supported for some time. I understand that many haven’t upgraded to v2 because, until now, there wasn’t a simple process to do this.

The good news is that the migration is now possible and straightforward, as long as you follow these instructions carefully and take your time. This upgrade also allows you to replace deprecated instance types (like the `CX` series) with newer ones. Note that this migration requires hetzner-k3s v2.2.4 or higher.

## Prerequisites

- [ ] I suggest installing the [hcloud utility](https://github.com/hetznercloud/cli). It will make it easier and faster to delete old master nodes.

## Upgrading configuration and first steps

- [ ] **Backup apps and data** – As with any migration, there’s some risk involved, so it’s better to be prepared in case things don’t go as planned.
- [ ] **Backup kubeconfig and the old config file**
- [ ] Uninstall the System Upgrade Controller
- [ ] Create a resolv file on existing nodes. You can do this manually or automate it using the `hcloud` CLI:
```bash
hcloud server list | awk '{print $4}' | tail -n +2 | while read ip; do
  echo "Setting DNS for ${ip}"
  ssh -n root@${ip} "echo nameserver 8.8.8.8 | tee /etc/k8s-resolv.conf"
  ssh -n root@${ip} "cat /etc/k8s-resolv.conf"
done
```
- [ ] Convert the config file to the new format. You can find guidance [here](https://github.com/vitobotta/hetzner-k3s/releases/tag/v2.0.0).
- [ ] Remove or comment out empty node pools from the config file.
- [ ] Set `embedded_registry_mirror`.`enabled` to `false` if necessary, depending on the current version of k3s (refer to [this documentation](https://docs.k3s.io/installation/registry-mirror)).
- [ ] Add `legacy_instance_type` to **ALL** node pools, including both masters and workers. Set it to the current instance type (even if it’s deprecated). **This step is critical for the migration**.
- [ ] Run the `create` command **using the latest version of hetzner-k3s and the new config file**.
- [ ] Wait for all CSI pods in `kube-system` to restart, and **make sure everything is running correctly**.

## Rotating control plane instances with the new instance type

Replace one master at a time (unless your cluster has a load balancer for the Kubernetes API, switch to another master's kube context before replacing `master1`):

- [ ] Drain and delete the master using both kubectl and the Hetzner console (or the `hcloud` CLI) to remove the actual instance.
- [ ] Rerun the `create` command to recreate the master with the new instance type. Wait for it to join the control plane and reach the "ready" status.
- [ ] SSH into each master and verify that the etcd members are updated and in sync:
```bash
sudo apt-get update
sudo apt-get install etcd-client

export ETCDCTL_API=3
export ETCDCTL_ENDPOINTS=https://[REDACTED].1:2379
export ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt
export ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt
export ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key

etcdctl member list
```

Repeat this process carefully for each master. After all three masters have been replaced:

- [ ] Rerun the `create` command once or twice to ensure the configuration is stable and the masters no longer restart.
- [ ] [Debug DNS resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/). If there are issues, restart the agents for DNS resolution with this command, then restart CoreDNS:
```bash
hcloud server list | grep worker | awk '{print $4}'| while read ip; do
  echo "${ip}"
  ssh -n root@${ip} "systemctl restart k3s-agent"
  sleep 10
done
```
- [ ] Address any issues with your workloads before proceeding to rotate the worker nodes.

## Rotating a worker node pool

- [ ] Increase the node count for the pool by 1.
- [ ] Run the `create` command to create the extra node needed during the pool rotation.

Replace one worker node at a time (except for the last one you just added):

- [ ] Drain a node.
- [ ] Delete the drained node using both kubectl and the Hetzner console (or the `hcloud` CLI).
- [ ] Rerun the `create` command to recreate the deleted node.
- [ ] Verify everything is working as expected before moving on to the next node in the pool.

Once all the existing nodes have been rotated:

- [ ] Drain the very last node in the pool (the one you added earlier).
- [ ] Verify everything is functioning correctly.
- [ ] Delete the last node using both kubectl and the Hetzner console (or the `hcloud` CLI).
- [ ] Update the `instance_count` for the node pool by reducing it by 1.
- [ ] Proceed with the next pool.

## Finalizing

- [ ] Remove the `legacy_instance_type` setting from both master and worker node pools.
- [ ] Rerun the `create` command once more to double-check everything.
- [ ] Optionally, convert the currently zonal cluster to a regional one with masters in different locations (see [this guide](Upgrading_a_cluster_from_1x_to_2x.md)).
