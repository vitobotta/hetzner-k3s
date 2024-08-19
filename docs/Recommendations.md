# Recommendations

## Larger clusters

The default configuration settings are pretty good for most small-medium clusters, so you can leave most settings unchanged if you want to go with a configuration that has been tested extensively.

However keep in mind that this default configuration - that uses a Hetzner private network with the default Flannel CNI built into k3s - may not be optimal for larger clusters:

1. Private networks in Hetzner cloud supports max 100 nodes, so I recommend you disable the private network in the configuration if you expect your cluster to grow beyond 100 nodes.
2. Flannel is fine for small to medium clusters, but performance starts to degrade with clusters made of several hundreds or thousands of nodes, so I recommend to switch to Cilium as CNI as its performance is excellent and scales well with very large clusters.

Notes:
- if you disable the private network due to the limitation mentioned above, encryption will be enforced at CNI level to secure the traffic between nodes over the public network.
- if you want to use something other than Cilium or Flannel (e.g. Calico), then you can disable the automatic setup of the CNI so you can install a CNI of your choice. We may add built in support for more CNIs in future releases.
- from v2.0.0 on you can also use an external SQL datastore like Postgres instead of the embedded etcd as datastore for the Kubernetes API. This can also help scaling larger clusters.

## Registry mirror

v2.0.0 introduces a setting to optionally enable the `embedded registry mirror` in k3s (see [this page](https://docs.k3s.io/installation/registry-mirror) for more information. This is basically an installation of [Spegel](https://github.com/spegel-org/spegel) which enables peer-to-peer distribution of container images between the nodes of a cluster. This can help avoid problems with nodes not being able to pull images because their IPs have been banned by registry (due to malicious use of the same IPs in the past or similar reason), because a node will try pulling an image from other nodes via the embedded registry mirror, before pulling the image from the upstream registry. This also speeds up pods creation because less time is spent downloading images from the upstream registries when deployments have many replicas spread across many nodes.

## Clusters using only the public network

If you disable the private network to be able to create a cluster with more than 100 nodes, then you cannot restrict access to the Kubernetes API by IP address because otherwise the API would not be accessible from the nodes. This limitation may be removed in a future release if a workaround is found, but for the time being the API must be accessible to 0.0.0.0/0 when the private network is disabled.
