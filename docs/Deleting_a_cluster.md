# Deleting a cluster

To delete a cluster, running

```bash
hetzner-k3s delete --config cluster_config.yaml
```

This will delete all the resources in the Hetzner Cloud project created by `hetzner-k3s` directly.

**NOTE:** the load balancers and persistent volumes created by deploying your applications must be deleted manually. This may be addressed in a future release.

Also note that being able to delete a cluster requires setting `protect_against_deletion` to `false` and that you enter the name of the cluster when you run the `delete` command to confirm that you really want to delete it. These measures are to prevent accidental deletion of a cluster that is not meant to be deleted.