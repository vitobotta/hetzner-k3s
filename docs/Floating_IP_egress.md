# Floating IP Egress

This guide explains how to configure a dedicated egress IP address for all outbound traffic from your cluster. This is useful when external services need to allowlist your cluster's IP address, or when you need a consistent source IP for outgoing connections.

This setup uses Cilium's egress gateway feature with a Hetzner floating IP.

## Enable Cilium Egress Gateway

In your cluster configuration, enable Cilium with the egress gateway feature:

```yaml
networking:
  cni:
    enabled: true
    mode: cilium
    cilium_egress_gateway: true
```

## Create a Dedicated Egress Node Pool

Add a worker node pool that will serve as the egress gateway. This node will route all outbound traffic through the floating IP:

```yaml
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

The taint ensures that regular workloads are not scheduled on this node—it's dedicated to handling egress traffic.

## Assign a Floating IP

1. Create a floating IP in the Hetzner Cloud Console (or via API/CLI) in the same location as your egress node
2. Assign the floating IP to the egress node
3. Configure the floating IP on the node's network interface (this may require additional cloud-init commands or manual configuration)

## Apply the Egress Gateway Policy

Create a `CiliumEgressGatewayPolicy` to route outbound traffic through the egress node:

```yaml
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

Replace `YOUR_FLOATING_IP` with your actual floating IP address.

Apply the policy:

```bash
kubectl apply -f egress-policy.yaml
```

## How It Works

- `selectors`: Matches all pods (empty `podSelector` means all pods in the cluster)
- `destinationCIDRs`: Routes all external traffic (`0.0.0.0/0`) through the egress gateway
- `excludedCIDRs`: Excludes internal/private network traffic (`10.0.0.0/8`) from being routed through the gateway, allowing pod-to-pod and pod-to-service communication to work normally
- `egressGateway`: Specifies which node handles the egress traffic and what source IP to use

Once configured, all outbound traffic from your cluster to external destinations will originate from your floating IP address.
