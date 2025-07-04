<h1 align="center">hetzner-k3s</h1>

<p align="center">
  <img src="https://github.com/vitobotta/hetzner-k3s/raw/main/logo.png" alt="hetzner-k3s logo" width="200" height="200" style="margin-left: auto;">
</p>

<h3 align="center">The simplest and quickest way to set up<br/>production-ready Kubernetes clusters on Hetzner Cloud.</h3>

## What is this?

This is a CLI tool designed to make it incredibly fast and easy to create and manage Kubernetes clusters on [Hetzner Cloud](https://hetzner.cloud/?ref=mqx6KKKwyook) (referral link, we both receive some credits) using [k3s](https://k3s.io/), a lightweight Kubernetes distribution from [Rancher](https://rancher.com/). In a test run, I created a **500**-node highly available cluster (3 masters, 497 worker nodes) in just **under 11 minutes** - though this was with only the public network, as private networks are limited to 100 instances per network. I think this might be a world record!

Hetzner Cloud is an awesome cloud provider that offers excellent service with the best performance-to-cost ratio available. They have data centers in Europe, USA and Singapore, making it a versatile choice.

k3s is my go-to Kubernetes distribution because it's lightweight, using far less memory and CPU, which leaves more resources for your workloads. It is also incredibly fast to deploy and upgrade because, thanks to being a single binary.

With `hetzner-k3s`, setting up a highly available k3s cluster with 3 master nodes and 3 worker nodes takes only **2-3 minutes**. This includes:

- Creating all the necessary infrastructure resources (instances, placement groups, load balancer, private network, and firewall).
- Deploying k3s to the nodes.
- Installing the [Hetzner Cloud Controller Manager](https://github.com/hetznercloud/hcloud-cloud-controller-manager) to provision load balancers immediately.
- installing the [Hetzner CSI Driver](https://github.com/hetznercloud/csi-driver) to handle persistent volumes using Hetzner's block storage.
- Installing the [Rancher System Upgrade Controller](https://github.com/rancher/system-upgrade-controller) to simplify and speed up k3s version upgrades.
- Installing the [Cluster Autoscaler](https://github.com/kubernetes/autoscaler) to enable autoscaling of node pools.
