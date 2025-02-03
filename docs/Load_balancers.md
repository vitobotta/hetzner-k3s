# Load balancers

Once your cluster is ready, you can start provisioning services of type `LoadBalancer` for your workloads, like the Nginx ingress controller. This is made possible by the Hetzner Cloud Controller Manager, which is installed automatically.

To configure the load balancers, you can add annotations to your services. At a minimum, you’ll need these two:

```yaml
load-balancer.hetzner.cloud/location: nbg1  # Ensures the load balancer is in the same network zone as your nodes
load-balancer.hetzner.cloud/use-private-ip: "true"  # Routes traffic between the load balancer and nodes through the private network, avoiding firewall changes
```

While the above are essential, I also recommend adding these annotations:

```yaml
load-balancer.hetzner.cloud/hostname: <a valid fqdn>
load-balancer.hetzner.cloud/http-redirect-https: 'false'
load-balancer.hetzner.cloud/name: <lb name>
load-balancer.hetzner.cloud/uses-proxyprotocol: 'true'
```

I usually set `load-balancer.hetzner.cloud/hostname` to a valid hostname, which I configure with the load balancer’s IP after it’s created. I combine this with the annotation `load-balancer.hetzner.cloud/uses-proxyprotocol: 'true'` to enable the proxy protocol. This is important because it allows my ingress controller and applications to detect the real client IP address. However, enabling the proxy protocol can cause issues with [cert-manager](https://cert-manager.io/docs/) failing http01 challenges. To fix this, Hetzner and some other providers recommend using a hostname instead of an IP for the load balancer. For more details, you can read the explanation [here](https://github.com/compumike/hairpin-proxy). If you want to see the actual client IP, I recommend using these two annotations.

The other annotations should be straightforward to understand. For a full list of available annotations, check out [this link](https://pkg.go.dev/github.com/hetznercloud/hcloud-cloud-controller-manager/internal/annotation).
