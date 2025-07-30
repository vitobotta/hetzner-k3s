# Deleting a Cluster

## Basic Deletion

To delete a cluster, you need to run the following command:

```bash
hetzner-k3s delete --config cluster_config.yaml
```

This command will remove all the resources in the Hetzner Cloud project that were created by `hetzner-k3s`.

## Important Considerations

### Protection Against Deletion

Additionally, to delete a cluster, you must ensure that `protect_against_deletion` is set to `false`. When you execute the `delete` command, you'll also need to enter the cluster's name to confirm the deletion. These steps are in place to avoid accidentally deleting a cluster you intended to keep.

### Resources Not Automatically Deleted

Keep in mind that the following resources created by your applications will not be deleted automatically. You'll need to remove those manually:

- **Load Balancers**: Load balancers created by your applications (via Services of type LoadBalancer)
- **Persistent Volumes**: Persistent volumes and their underlying storage
- **Floating IPs**: Any floating IPs you've manually attached to instances
- **Snapshots**: Any snapshots created from instances

This behavior is by design to prevent accidental data loss. These resources might be improved in future updates.

## Manual Cleanup Steps

### Before Deleting the Cluster

1. **Backup Important Data**: Ensure you have backups of any important data stored in persistent volumes
2. **Export Application Configurations**: Save any Kubernetes manifests, Helm values, or configurations you might need later
3. **Note Load Balancer IPs**: If you have applications with public IPs, note them down as they might change if you recreate the cluster

### After Deleting the Cluster

#### Manual Cleanup

You can easily delete any remaining resources using the **Hetzner Cloud Console**:

1. **Log in** to your Hetzner Cloud Console
2. **Navigate to your project**
3. **Delete remaining resources** from the left sidebar:
   - **Load Balancers** → Select and delete any application load balancers
   - **Volumes** → Select and delete any persistent volumes
   - **Floating IPs** → Select and delete any unused floating IPs
   - **Snapshots** → Select and delete any unnecessary snapshots

This visual approach is recommended as it's easier to identify which resources belong to your cluster and avoid accidental deletions.

## Troubleshooting Deletion Issues

### Cluster Still Protected

If you get an error about the cluster being protected:

1. **Check Configuration**: Ensure `protect_against_deletion: false` is set in your config file
2. **Verify Cluster Name**: Make sure you're entering the correct cluster name when prompted
3. **Check kubeconfig**: Sometimes the cluster name is read from the kubeconfig location

### Resources Stuck in Deletion

If some resources are stuck and not being deleted:

1. **Check Hetzner Console**: Log in to the Hetzner Cloud Console to see the current state
2. **Wait and Retry**: Sometimes there's a delay in API updates, wait a few minutes and retry

### Network Resources Not Deleted

If networks, firewall rules, or other network resources remain:

1. **Check Dependencies**: Make sure no instances are still using the network, load balancer or firewall
2. **Delete Manually**: Use the Hetzner Console or API to clean up remaining network resources

---

## Alternative: Delete Entire Project

If your cluster is the only thing in the Hetzner Cloud project, you might find it easier to delete the entire project instead:

1. **Go to Hetzner Cloud Console**
2. **Navigate to your project**
3. **Click on "Settings"**
4. **Select "Delete Project"**

This will delete everything in the project, including any resources you might have forgotten about.

> **Warning**: This is irreversible! Only do this if you're certain you don't need anything in the project.

---

## Best Practices

### Planning for Deletion

When setting up your cluster, consider:

1. **Use Projects Wisely**: Consider creating separate projects for different clusters or environments
2. **Document Dependencies**: Keep track of external resources that depend on your cluster

### Post-Deletion Checklist

After deleting your cluster, verify:

- [ ] No instances are running
- [ ] No load balancers are active
- [ ] No volumes are attached
- [ ] No floating IPs are allocated
- [ ] Network usage has stopped
- [ ] Billing reflects the changes

### Cost Monitoring

Monitor your Hetzner Cloud billing dashboard for a few days after deletion to ensure:

- No unexpected charges appear
- All compute resources have been properly terminated
- Network and storage costs stop accumulating

If you see unexpected charges, check for orphaned resources that might need manual cleanup.
