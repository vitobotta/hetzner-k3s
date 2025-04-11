# Recommendations

## Larger Clusters

The default configuration works well for small to medium-sized clusters, so you don’t need to change much if you want a simple, reliable setup..

For larger clusters, thought, the default setup is quite limiting. Hetzner’s private networks, which are used in hetzner-k3s' default configuration, only support up to 100 nodes. If you your cluster is going to grow beyond that, I recommend disabling the private network in your configuration.

Support for large clusters has gotten a lot better since version 2.2.8. Before that, you could create large clusters using the public network, and all the traffic between the nodes was encrypted and authenticated. However this meant opening the Kubernetes API port on the master nodes and the Wireguard port on all nodes to the public Internet, which introduced some security risks.

Here’s what changed in version 2.2.8:

Instead of using Hetzner’s firewall, which is slow to update and can be problematic when you’re making a lot of changes at once, a custom firewall was added. This firewall keeps the traffic between nodes secure without opening any ports to the public, unless you specifically want to.
One issue with the firewall is that it can’t know the IPs of the nodes in advance, especially when they’re created dynamically or with autoscaling. To solve this, an "IP query server" was set up as a simple container. This server checks the Hetzner API every 30 seconds to get the list of all node IPs in the project. Then, the firewall on each node regularly polls this IP query server to update its rules and keep everything secure. This solution is simple and effective, and it means you don’t need to open the Kubernetes API port or the Wireguard port to the public unless you really want to. It also removes the need for manual firewall updates, as everything happens automatically.

### Setting up the IP query server

The IP query server runs as a simple container. You can easily set it up on any Docker-enabled server using the `docker-compose.yml` file in the `ip-query-server` folder of this repository. This compose project also runs Caddy as a web server, so you can use a domain name with the server. Just replace `example.com` in the Caddyfile with your actual domain name and `mail@example.com` with the email address you'll use to request a certificate from Let's Encrypt via Caddy.

There's nothing else to configure for the server itself. The firewall on each node sends the server the token for the Hetzner project, which the server uses to get the list of node IPs.

Once the server is up and running, change your hetzner-k3s configuration and set `networking.public_network.hetzner_ips_query_server_url` to your server's URL, and `use_local_firewall` to `true`.

For a production setup, I recommend having two instances of the server behind a load balancer for better availability.

### Additional notes about large clusters

- If you disable the private network due to the node limit, encryption will be applied at the CNI level to secure communication between nodes over the public network.
- If you prefer a CNI other than Cilium or Flannel (e.g., Calico), you can disable automatic CNI setup and install your preferred CNI manually. We may add support for more CNIs in future releases.
- Starting with v2.0.0, you can use an external SQL datastore like Postgres instead of the built-in etcd for the Kubernetes API. This can also help with scaling larger clusters.

## Embedded Registry Mirror

In v2.0.0, there’s a new option to enable the `embedded registry mirror` in k3s. You can find more details [here](https://docs.k3s.io/installation/registry-mirror). This feature uses [Spegel](https://github.com/spegel-org/spegel) to enable peer-to-peer distribution of container images across cluster nodes.

This can help in situations where nodes face issues pulling images because their IPs have been blocked by registries (due to past misuse or similar reasons). With this setup, a node will first try pulling an image from other nodes via the embedded registry mirror before reaching out to the upstream registry. This not only resolves access issues but also speeds up pod creation, especially for deployments with many replicas spread across multiple nodes. To enable it, set `embedded_registry_mirror`.`enabled` to `true`. Just make sure your k3s version supports this feature by checking the linked page.

### Clusters Using Only the Public Network

If you disable the private network to allow your cluster to grow beyond 100 nodes, you won’t be able to restrict access to the Kubernetes API by IP address. This is because the API must be accessible from all nodes, and blocking IPs would prevent communication.

This limitation might be addressed in future releases if a workaround is found. For now, the API must be open to 0.0.0.0/0 when the private network is disabled.
