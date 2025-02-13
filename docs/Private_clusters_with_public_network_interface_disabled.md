# Private clusters with public network interface disabled

By default, network access to nodes in a cluster created with hetzner-k3s is limited to the networks listed in the configuration file. Some users might want to completely turn off the public interface on their nodes instead.

This page offers a reference configuration to help you disable the public interface. Keep in mind that some steps might vary depending on the operating system you choose for your nodes. The example configuration has been tested successfully with Debian 12, as it's a bit simpler to work with compared to other OSes.

Please note that this configuration is designed for new clusters only. I haven't tested if it works to convert an existing cluster to one with the public interface disabled.

When setting up a cluster with disabled public network interfaces, remember you'll need a NAT gateway to access the cluster from outside Hetzner Cloud. Without it, your nodes won't be able to connect to the internet, and hetzner-k3s won’t be able to install k3s on those nodes.

Another important thing to consider is that with the public network interface disabled on all nodes, you can't run hetzner-k3s from a computer outside the cluster's private network. So, you'll need to run hetzner-k3s from a cloud instance within the private network. You could use the same instance you're using as your NAT gateway for this purpose too.

## Prerequisite: NAT Gateway

First off, you need to set up a NAT gateway for your Hetzner Cloud network. Follow the instructions on [this page](https://community.hetzner.com/tutorials/how-to-set-up-nat-for-cloud-networks).

The guide uses Debian as an example, so make sure to review the page and adjust any settings according to the operating system you choose for your cluster nodes and the NAT gateway instance.

The TL;DR is this:

- [ ] First, create a private network in the Hetzner project where your cluster will reside. Choose any subnet you like, but for reference purposes, let's assume it’s 10.0.0.0/16.

- [ ] Next, set up a cloud instance to act as your NAT gateway. Ensure it has a public IP address and connects to the private network you just created.

- [ ] Then, add a route on your private network for `0.0.0.0/0`, directing it to the IP address of your NAT gateway instance, which you can select from a dropdown menu.

- [ ] Finally, on the NAT gateway instance itself, tweak `/etc/network/interfaces`. Add these lines or adjust existing ones for your private network interface:

```
auto enp7s0
iface enp7s0 inet dhcp
    post-up echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up iptables -t nat -A POSTROUTING -s '10.0.0.0/16' -o enp7s0 -j MASQUERADE
```

Replace `10.0.0.0/16` with your actual subnet if it's different. Also, make sure to use the correct name for your private network interface if `enp7s0` isn't right—find this with the `ifconfig` command.

- [ ] Lastly, restart your NAT gateway instance to apply these changes.


## Cluster configuration

- [ ] Edit the configuration file for your cluster and set both `ipv4` and `ipv6` to `false`:

```yaml
  public_network:
    ipv4: true
    ipv6: true
```

Also configure the allowed networks:

```yaml
  allowed_networks:
    ssh:
      - 0.0.0.0/0
    api:
      - 0.0.0.0/0
```

- [ ] Since you're setting up a private cluster, it makes sense to turn off the load balancer for the Kubernetes API. You can do this by setting `create_load_balancer_for_the_kubernetes_api` to `false`.

- [ ] Also, if you want to use an OS image other than the default (`ubuntu-24.04`), you can configure it accordingly. For example, if you prefer Debian 12, you can set it up like this:

```yaml
image: debian-12
autoscaling_image: debian-12
```

- [ ] Next, you need to set up the `post_create_commands` section with a series of important steps. These steps will ensure that the nodes in your clusters use the NAT gateway to access the Internet.:

```yaml
post_create_commands:
- apt update
- apt upgrade -y
- apt install ifupdown resolvconf -y
- echo "auto enp7s0" > /etc/network/interfaces.d/60-private
- echo "iface enp7s0 inet dhcp" >> /etc/network/interfaces.d/60-private
- echo "    post-up ip route add default via 10.0.0.1"  >> /etc/network/interfaces.d/60-private
- echo "[Resolve]" > /etc/systemd/resolved.conf
- echo "DNS=1.1.1.1 1.0.0.1" >> /etc/systemd/resolved.conf
- ifdown enp7s0
- ifup enp7s0
- systemctl start resolvconf
- systemctl enable resolvconf
- echo "nameserver 1.1.1.1" >> /etc/resolvconf/resolv.conf.d/head
- echo "nameserver 1.0.0.1" >> /etc/resolvconf/resolv.conf.d/head
- resolvconf --enable-updates
- resolvconf -u
```

Replace `enp7s0` with your network interface name, and `10.0.0.1` with the correct gateway IP address for your subnet. Note that this is not the IP address of the NAT gateway instance; it's simply the first IP in the range.

One important thing to remember: these simple commands work great if you're using the same type of instances, like all AMD instances, for both your master and worker node pools. We're referencing a specific private network interface name here.

If you plan on using different types of instances in your cluster, you'll need to tweak these commands to use a more flexible method for identifying the correct private interface on each node.

## Creating the cluster

Run the `create` command with hetzner-k3s as usual, but use this updated configuration from an instance connected to the same private network. For example, you can use the NAT gateway instance if you don't want to create another one.

The nodes will be able to access the Internet through the NAT gateway. Therefore, hetzner-k3s should complete creating the cluster successfully.
