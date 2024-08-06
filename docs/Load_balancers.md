# Load balancers

Once the cluster is ready, you can already provision services of type LoadBalancer for your workloads (such as the Nginx ingress controller for example) thanks to the Hetzner Cloud Controller Manager that is installed automatically.

There are some annotations that you can add to your services to configure the load balancers. At a minimum your need these two:

```yaml
load-balancer.hetzner.cloud/location: nbg1 # must ensure the network location of the load balancer is same as for the nodes
load-balancer.hetzner.cloud/use-private-ip: "true" # ensures the traffic between LB and nodes goes through the private network, so you don't need to change anything in the firewall
```

The above are required, but I also recommend these:

```yaml
load-balancer.hetzner.cloud/hostname: <a valid fqdn>
load-balancer.hetzner.cloud/http-redirect-https: 'false'
load-balancer.hetzner.cloud/name: <lb name>
load-balancer.hetzner.cloud/uses-proxyprotocol: 'true'
```

I set `load-balancer.hetzner.cloud/hostname` to a valid hostname that I configure (after creating the load balancer) with the IP of the load balancer; I use this together with the annotation `load-balancer.hetzner.cloud/uses-proxyprotocol: 'true'` to enable the proxy protocol. Reason: I enable the proxy protocol on the load balancers so that my ingress controller and applications can "see" the real IP address of the client. However when this is enabled, there is a problem where [cert-manager](https://cert-manager.io/docs/) fails http01 challenges; you can find an explanation of why [here](https://github.com/compumike/hairpin-proxy) but the easy fix provided by some providers - including Hetzner - is to configure the load balancer so that it uses a hostname instead of an IP. Again, read the explanation for the reason but if you care about seeing the actual IP of the client then I recommend you use these two annotations.

The other annotations should be self explanatory. You can find a list of the available annotations [here](https://pkg.go.dev/github.com/hetznercloud/hcloud-cloud-controller-manager/internal/annotation).

**Note**: in a future release it will be possible to configure ingress controllers with host ports, so it will be possible to use an ingress without having to buy a load balancer, but for the time being a load balancer is still required.
