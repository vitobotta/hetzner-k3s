# Set up a private network and a vSwitch prior to that

https://docs.hetzner.com/cloud/networks/connect-dedi-vswitch/

Follow the instructions and make sure cloud nodes & robot nodes can ping each other

# Cilium settings

Encryption needs to be disabled. Cilium has been tested and works well.

```
  cni:
    enabled: true
    encryption: false
    mode: cilium
```

# You can then add the node to the k3s

1. Get the token one of the master nodes

`cat /var/lib/rancher/k3s/server/token`

2. Start the agent on the dedicated node (change MASTER_IP & TOKEN)

```
curl -sfL https://get.k3s.io | \
      K3S_URL=https://MASTER_IP:6443 \
      K3S_TOKEN=TOKEN \
      K3S_CONTAINERD_SNAPSHOTTER='fuse-overlayfs' \
      sh -s - --node-label dedicated=true
```
