To delete a cluster, you need to run the following command:

```bash
hetzner-k3s delete --config cluster_config.yaml
```

This command will remove all the resources in the Hetzner Cloud project that were created by `hetzner-k3s`.

Keep in mind that the load balancers and persistent volumes created by your applications will not be deleted automatically. You’ll need to remove those manually. This might be improved in a future update.

Additionally, to delete a cluster, you must ensure that `protect_against_deletion` is set to `false`. When you execute the `delete` command, you’ll also need to enter the cluster’s name to confirm the deletion. These steps are in place to avoid accidentally deleting a cluster you intended to keep.
