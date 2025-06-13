To allow for a unique IP for every call getting from your Cluster, enable Cilim egress

```
networking:
  cni:
    enabled: true
    mode: cilium
    cilium_egress_gateway: true
```

Also add a node that will be the middle man

```
worker_node_pools:
  - name: egress
    instance_type: cax21
    location: hel1
    instance_count: 1
    autoscaling:
      enabled: false
    labels:
      - key: node.kubernetes.io/role
        value: "egress"
    taints:
      - key: node.kubernetes.io/role
        value: egress:NoSchedule
```

Then assign a floating IP to that node.

```
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: egress-global
spec:
  selectors:
    - podSelector: {}

  destinationCIDRs:
    - "0.0.0.0/0"
  excludedCIDRs:
    - "10.0.0.0/8"

  egressGateway:
    nodeSelector:
      matchLabels:
        node.kubernetes.io/role: egress
    egressIP: YOUR_FLOATING_IP
```

That policy makes it so the outgoing traffic goes from YOUR_FLOATING_IP
