# Maintenance

## Adding nodes

To add one or more nodes to a node pool, just change the instance count in the configuration file for that node pool and re-run the create command.

**Important**: if you are increasing the size of a node pool created prior to v0.5.7, please see [this thread](https://github.com/vitobotta/hetzner-k3s/issues/80).

## Scaling down a node pool

To make a node pool smaller:

- decrease the instance count for the node pool in the configuration file so that those extra nodes are not recreated in the future
- delete the nodes from Kubernetes (`kubectl delete node <name>`)
- delete the instances from the cloud console if the Cloud Controller Manager doesn't delete it automatically (make sure you delete the correct ones 🤭)

In a future release I will add some automation for the cleanup.

## Replacing a problematic node

- delete the node from Kubernetes (`kubectl delete node <name>`)
- delete the correct instance from the cloud console
- re-run the `create` command. This will re-create the missing node and have it join to the cluster

## Converting a non-HA cluster to HA

It's easy to convert a non-HA with a single master cluster to HA with multiple masters. Just change the masters instance count and re-run the `create` command. This will create a load balancer for the API server and update the kubeconfig so that all the API requests go through the load balancer.

## Replacing the seed master

When creating a new cluster, the seed master (or first master) in a HA configuration is `master1`. The seed master will change if you delete `master1` due to some issues with the node so it gets recreated. Whenever the seed master changes, k3s must be restarted on the existing masters.

___
## Upgrading to a new version of k3s

If it's the first time you upgrade the cluster, all you need to do to upgrade it to a newer version of k3s is run the following command:

```bash
hetzner-k3s upgrade --config cluster_config.yaml --new-k3s-version v1.27.1-rc2+k3s1
```

So you just need to specify the new k3s version as an additional parameter and the configuration file will be updated with the new version automatically during the upgrade. To see the list of available k3s releases run the command `hetzner-k3s releases`.

Note: (single master clusters only) the API server will briefly be unavailable during the upgrade of the controlplane.

To check the upgrade progress, run `watch kubectl get nodes -owide`. You will see the masters being upgraded one per time, followed by the worker nodes.

NOTE: if you haven't used the tool in a while before upgrading, you may need to delete the file `cluster_config.yaml.example` in your temp folder to refresh the list of available k3s versions.


### What to do if the upgrade doesn't go smoothly

If the upgrade gets stuck for some reason, or it doesn't upgrade all the nodes:

1. Clean up the existing upgrade plans and jobs, and restart the upgrade controller

```bash
kubectl -n system-upgrade delete job --all
kubectl -n system-upgrade delete plan --all

kubectl label node --all plan.upgrade.cattle.io/k3s-server- plan.upgrade.cattle.io/k3s-agent-

kubectl -n system-upgrade rollout restart deployment system-upgrade-controller
kubectl -n system-upgrade rollout status deployment system-upgrade-controller
```

You can also check the logs of the system upgrade controller's pod:

```bash
kubectl -n system-upgrade \
  logs -f $(kubectl -n system-upgrade get pod -l pod-template-hash -o jsonpath="{.items[0].metadata.name}")
```

A final note about upgrades is that if for some reason the upgrade gets stuck after upgrading the masters and before upgrading the worker nodes, just cleaning up the resources as described above might not be enough. In that case also try running the following to tell the upgrade job for the workers that the masters have already been upgraded, so the upgrade can continue for the workers:

```bash
kubectl label node <master1> <master2> <master2> plan.upgrade.cattle.io/k3s-server=upgraded
```

___
## Upgrading the OS on nodes

- consider adding a temporary node during the process if you don't have enough spare capacity in the cluster
- drain one node
- update etc
- reboot
- uncordon
- proceed with the next node

If you want to automate this process I recommend you install the [Kubernetes Reboot Daemon ](https://kured.dev/) ("Kured"). For this to work properly, make sure the OS you choose for the nodes has unattended upgrades enabled at least for security updates. For example if the image is Ubuntu, you can add this to the configuration file before running the `create` command:

```yaml
additional_packages:
- unattended-upgrades
- update-notifier-common
post_create_commands:
- sudo systemctl enable unattended-upgrades
- sudo systemctl start unattended-upgrades
```

Check the Kured documentation for configuration options like maintenance window etc.

