# Storage

Once the cluster is ready you can create persistent volumes out of the box with the default storage class `hcloud-volumes`, since the Hetzner CSI driver is installed automatically. This will use Hetzner's block storage (based on Ceph so it's replicated and highly available) for your persistent volumes. Note that the minimum size of a volume is 10Gi. If you specify a smaller size for a volume, the volume will be created with a capacity of 10Gi anyway.

For workloads like databases that benefit from max IOPS there's also the `local-path` storage class. It is disabled by default but you can enable it by setting `local_path_storage_class.enabled` to `true` in the config file. See [this page](https://docs.k3s.io/storage) for more details.
