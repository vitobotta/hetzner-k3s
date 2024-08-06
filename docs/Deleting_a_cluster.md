# Deleting a cluster

To delete a cluster, running

```bash
hetzner-k3s delete --config cluster_config.yaml
```

This will delete all the resources in the Hetzner Cloud project created by `hetzner-k3s` directly.

**NOTE:** at the moment instances created by the cluster autoscaler, as well as load balancers and persistent volumes created by deploying your applications must be deleted manually. This may be addressed in a future release.

