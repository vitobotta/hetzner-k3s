# Recommendations

### Larger Clusters

The default configuration works well for small to medium-sized clusters, so you don’t need to change most settings if you prefer a configuration that has been thoroughly tested.

However, for larger clusters, the default setup—which uses Hetzner’s private network and the Flannel CNI included in k3s—might not be the best choice. Here’s why:

1. Hetzner’s private network supports a maximum of 100 nodes. If you expect your cluster to grow beyond this limit, I suggest disabling the private network in your configuration.
2. Flannel performs well for smaller clusters, but its performance declines with clusters of several hundred or thousands of nodes. For better scalability, I recommend switching to Cilium as your CNI, as it handles large clusters efficiently.

Additional notes:

- If you disable the private network due to the node limit, encryption will be applied at the CNI level to secure communication between nodes over the public network.
- If you prefer a CNI other than Cilium or Flannel (e.g., Calico), you can disable automatic CNI setup and install your preferred CNI manually. We may add support for more CNIs in future releases.
- Starting with v2.0.0, you can use an external SQL datastore like Postgres instead of the built-in etcd for the Kubernetes API. This can also help with scaling larger clusters.

### Embedded Registry Mirror

In v2.0.0, there’s a new option to enable the `embedded registry mirror` in k3s. You can find more details [here](https://docs.k3s.io/installation/registry-mirror). This feature uses [Spegel](https://github.com/spegel-org/spegel) to enable peer-to-peer distribution of container images across cluster nodes.

This can help in situations where nodes face issues pulling images because their IPs have been blocked by registries (due to past misuse or similar reasons). With this setup, a node will first try pulling an image from other nodes via the embedded registry mirror before reaching out to the upstream registry. This not only resolves access issues but also speeds up pod creation, especially for deployments with many replicas spread across multiple nodes. To enable it, set `embedded_registry_mirror`.`enabled` to `true`. Just make sure your k3s version supports this feature by checking the linked page.

### Clusters Using Only the Public Network

If you disable the private network to allow your cluster to grow beyond 100 nodes, you won’t be able to restrict access to the Kubernetes API by IP address. This is because the API must be accessible from all nodes, and blocking IPs would prevent communication.

This limitation might be addressed in future releases if a workaround is found. For now, the API must be open to 0.0.0.0/0 when the private network is disabled.
