# Storage

Once your cluster is set up, you can easily create persistent volumes using the default storage class `hcloud-volumes`. The Hetzner CSI driver is automatically installed, allowing you to use Hetzner's block storage for these volumes. This storage is based on Ceph, ensuring it’s both replicated and highly available. Keep in mind that the minimum size for a volume is 10Gi. If you try to create a smaller volume, it will still be created with a 10Gi capacity.

For workloads that require maximum IOPS, such as databases, there’s also the `local-path` storage class. This is disabled by default, but you can enable it by setting `local_path_storage_class`.`enabled` to `true` in the configuration file. For more details, refer to [this page](https://docs.k3s.io/storage).
