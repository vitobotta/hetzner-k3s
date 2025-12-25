![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/vitobotta/hetzner-k3s)
![GitHub Release Date](https://img.shields.io/github/release-date/vitobotta/hetzner-k3s)
![GitHub last commit](https://img.shields.io/github/last-commit/vitobotta/hetzner-k3s)
![GitHub issues](https://img.shields.io/github/issues-raw/vitobotta/hetzner-k3s)
![GitHub pull requests](https://img.shields.io/github/issues-pr-raw/vitobotta/hetzner-k3s)
![GitHub](https://img.shields.io/github/license/vitobotta/hetzner-k3s)
![GitHub Discussions](https://img.shields.io/github/discussions/vitobotta/hetzner-k3s)
![GitHub top language](https://img.shields.io/github/languages/top/vitobotta/hetzner-k3s)

![GitHub forks](https://img.shields.io/github/forks/vitobotta/hetzner-k3s?style=social)
![GitHub Repo stars](https://img.shields.io/github/stars/vitobotta/hetzner-k3s?style=social)

---

```
 _          _                            _    _____
| |__   ___| |_ _____ __   ___ _ __     | | _|___ / ___
| '_ \ / _ \ __|_  / '_ \ / _ \ '__|____| |/ / |_ \/ __|
| | | |  __/ |_ / /| | | |  __/ | |_____|   < ___) \__ \
|_| |_|\___|\__/___|_| |_|\___|_|       |_|\_\____/|___/
```

# The simplest and quickest way to set up production-ready Kubernetes clusters on Hetzner Cloud.

<p align="center">
  <img src="logo-v2.png" alt="hetzner-k3s logo" width="200" height="200" style="margin-left: auto;">
</p>

## What is this?

hetzner-k3s is a CLI tool designed to make it incredibly easy and fast and to create and manage Kubernetes clusters on [Hetzner Cloud](https://hetzner.cloud/?ref=mqx6KKKwyook) (referral link, we both receive some credits) using [k3s](https://k3s.io/), a lightweight Kubernetes distribution created by [Rancher](https://rancher.com/). In a test run, I created a **500**-node highly available cluster (3 masters, 497 worker nodes) in just **under 11 minutes** - though this was with only the public network, as private networks are limited to 100 instances per network. I think this might be a world record!

Hetzner Cloud is an awesome cloud provider that offers excellent service with the best performance-to-cost ratio available. They have data centers in Europe, USA and Singapore, making it a versatile choice.

k3s is my go-to Kubernetes distribution because it's lightweight, using far less memory and CPU, which leaves more resources for your workloads. It is also incredibly fast to deploy and upgrade because, thanks to being a single binary.

With `hetzner-k3s`, setting up a highly available k3s cluster with 3 master nodes and 3 worker nodes takes only **2-3 minutes**. This includes:

- Creating all the necessary infrastructure resources (instances, load balancer, private network, and firewall).
- Deploying k3s to the nodes.
- Installing the [Hetzner Cloud Controller Manager](https://github.com/hetznercloud/hcloud-cloud-controller-manager) to provision load balancers immediately (enabled by default, can be disabled with `addons.csi_driver.enabled: false`).
- Installing the [Hetzner CSI Driver](https://github.com/hetznercloud/csi-driver) to handle persistent volumes using Hetzner's block storage (enabled by default, can be disabled with `addons.csi_driver.enabled: false`).
- Installing the [Rancher System Upgrade Controller](https://github.com/rancher/system-upgrade-controller) to simplify and speed up k3s version upgrades.
- Installing the [Cluster Autoscaler](https://github.com/kubernetes/autoscaler) to enable autoscaling of node pools.
- K3s built-in addons Traefik, ServiceLB and metrics-server are disabled by default for a leaner control-plane. You can enable them individually with `addons.traefik.enabled`, `addons.servicelb.enabled`, or `addons.metrics_server.enabled` in the configuration file.

If you're curious about why hetzner-k3s is a good choice for setting up your clusters and how it stacks up against other options, I highly recommend you check out [this page](https://vitobotta.github.io/hetzner-k3s/Comparison_with_other_tools.md/).

---

## Quick Start

For a step-by-step guide on setting up a cluster with the most common configuration, check out the [documentation](https://vitobotta.github.io/hetzner-k3s/Setting_up_a_cluster/).

---

___
## Who am I?

Hey there! I’m the Lead Platform Architect at [Brella](https://www.brella.io/), an event management platform based in Finland. You could say I’m the person who ensures everything works smoothly. That includes handling coding, infrastructure, and supporting the rest of the development team.

Outside of my main job, I spend time looking for security bugs as a bug bounty hunter. My goal is to find vulnerabilities in web applications and report them responsibly so they can be fixed.

If you’d like to connect or just have a chat, feel free to check out my public profile [here](https://vitobotta.com/). You’ll find all the necessary links there. I may also be available for consultancies around hetzner-k3s and related topics.

---

## Docs

All the documentation is available [here](https://vitobotta.github.io/hetzner-k3s/).

---

## Sponsors

If you or your company find this project useful, please consider [sponsoring its development](https://github.com/sponsors/vitobotta). Your support helps keep this project actively maintained.

### Platinum Sponsors

A special thank you to <a href="https://alamos.gmbh">Alamos GmbH</a> for sponsoring the development of awesome features!

<a href="https://alamos.gmbh"><img src="Alamos_black.svg" alt="Alamos" height="80"></a>

### Backers

Also thanks to [@deubert-it](https://github.com/deubert-it), [@jonasbadstuebner](https://github.com/jonasbadstuebner), [@ricristian
](https://github.com/ricristian), [@QuentinFAIDIDE](https://github.com/QuentinFAIDIDE) for their support!

___
## Code of conduct

Everyone interacting in the hetzner-k3s project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/vitobotta/hetzner-k3s/blob/main/CODE_OF_CONDUCT.md).

___
## License

This tool is available as open source under the terms of the [MIT License](https://github.com/vitobotta/hetzner-k3s/blob/main/LICENSE.txt).

___

## Stargazers over time

[![Stargazers over time](https://starchart.cc/vitobotta/hetzner-k3s.svg)](https://starchart.cc/vitobotta/hetzner-k3s)
