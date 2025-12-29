<h1 align="center">hetzner-k3s</h1>

<p align="center">
  <img src="https://github.com/vitobotta/hetzner-k3s/raw/main/logo-v2.png" alt="hetzner-k3s logo" width="200" height="200" style="margin-left: auto;">
</p>

<h3 align="center">The easiest and fastest way to create<br/>production-ready Kubernetes clusters on Hetzner Cloud</h3>

---

!!! info "📢 Shape the Future of hetzner-k3s"

    I'm exploring a dual-licensing model: free for personal and non-commercial use, with a reasonable fee for commercial/profit-making activities. I'd love your input on this direction!

    **[Join the discussion →](https://github.com/vitobotta/hetzner-k3s/discussions/703)**

---

## What is hetzner-k3s?

**hetzner-k3s** is a CLI tool that creates fully-configured Kubernetes clusters on [Hetzner Cloud](https://hetzner.cloud/?ref=mqx6KKKwyook) in minutes. It uses [k3s](https://k3s.io/), a lightweight Kubernetes distribution by Rancher, and automatically configures everything you need for production workloads.

### Key Highlights

| Metric | Value |
|--------|-------|
| **Time to create a 6-node HA cluster** | 2-3 minutes |
| **Tested scale** | 500 nodes in under 11 minutes |
| **Dependencies** | Just the CLI tool |
| **Platform fees** | None — you only pay Hetzner |

### What Gets Installed Automatically

- **k3s** — lightweight, certified Kubernetes
- **Hetzner Cloud Controller Manager** — automatic load balancer provisioning
- **Hetzner CSI Driver** — persistent volumes via Hetzner block storage
- **System Upgrade Controller** — zero-downtime k3s upgrades
- **Cluster Autoscaler** — automatic node scaling based on demand
- **Private networking and firewall** — secure cluster communication

---

## Getting Started

| | |
|---|---|
| **[Installation](Installation.md)** | Install hetzner-k3s on macOS, Linux, or Windows (via WSL) |
| **[Create Your First Cluster](Creating_a_cluster.md)** | Configuration reference and cluster creation |
| **[Complete Tutorial](Setting_up_a_cluster.md)** | Set up a cluster with ingress, TLS, and a sample application |
| **[Why hetzner-k3s?](Comparison_with_other_tools.md)** | Compare to managed services and Terraform-based alternatives |

---

## Why Choose hetzner-k3s?

### Speed Without Shortcuts

A 3-master, 3-worker highly available cluster takes just 2-3 minutes to create. This includes provisioning all infrastructure (instances, load balancer, private network, firewall) and deploying k3s with all essential components.

In stress testing, a 500-node cluster (3 masters, 497 workers) was created in under 11 minutes.

### Simplicity That Scales

- **No Terraform or Packer** — a single CLI tool handles everything
- **No management cluster** — unlike Cluster API or Claudie, you don't need Kubernetes to create Kubernetes
- **Simple YAML configuration** — human-readable and version-controllable
- **Idempotent operations** — run `create` multiple times safely; it picks up where it left off

### Complete Control

- **Your credentials stay local** — the Hetzner API token never leaves your machine
- **No third-party access** — unlike managed services, no external party can access your clusters
- **Open source (MIT License)** — inspect, modify, and contribute to the code
- **No recurring fees** — you only pay Hetzner for infrastructure

### Production-Ready Defaults

- **High availability** — distribute masters and workers across locations
- **Autoscaling** — scale worker pools based on resource demands
- **Private networking** — cluster traffic stays off the public internet
- **Automatic upgrades** — the System Upgrade Controller handles rolling updates

---

## Documentation Structure

### Getting Started
- [Installation](Installation.md) — Install hetzner-k3s on your system
- [Creating a Cluster](Creating_a_cluster.md) — Configuration reference and cluster creation
- [Setting Up a Complete Stack](Setting_up_a_cluster.md) — Ingress, TLS, and application deployment

### Operations
- [Cluster Maintenance](Maintenance.md) — Adding nodes, upgrades, and scaling
- [Load Balancers](Load_balancers.md) — Configuring Hetzner load balancers
- [Storage](Storage.md) — Persistent volumes and storage options
- [Deleting a Cluster](Deleting_a_cluster.md) — Clean removal of cluster resources

### Advanced Topics
- [Recommendations](Recommendations.md) — Best practices for different cluster sizes
- [Large Clusters (100+ nodes)](Recommendations.md#large-clusters-50-nodes) — Configuration for large-scale deployments
- [Private Clusters](Private_clusters_with_public_network_interface_disabled.md) — Clusters without public IPs
- [Masters in Different Locations](Masters_in_different_locations.md) — Regional high availability
- [Floating IP Egress](Floating_IP_egress.md) — Consistent outbound IP addresses

### Reference
- [Comparison with Other Tools](Comparison_with_other_tools.md) — How hetzner-k3s compares to alternatives
- [Troubleshooting](Troubleshooting.md) — Common issues and solutions
- [Upgrading from v1.x to v2.x](Upgrading_a_cluster_from_1x_to_2x.md) — Migration guide
- [Important Upgrade Notes](Important_upgrade_notes.md) — Version-specific considerations

### Community
- [Contributing and Support](Contributing_and_support.md) — How to contribute and get help

---

## Why Hetzner Cloud?

[Hetzner Cloud](https://hetzner.cloud/?ref=mqx6KKKwyook) offers exceptional value for Kubernetes workloads:

- **Up to 80% lower costs** than AWS, Google Cloud, and Azure
- **Transparent, all-inclusive pricing** — traffic, IPv4/IPv6, DDoS protection, and firewalls included
- **Six global locations** — Germany (Nuremberg, Falkenstein), Finland (Helsinki), USA (Ashburn, Hillsboro), Singapore
- **Flexible instance types** — x86 and ARM architectures, including cost-effective ARM instances (CAX) for budget-friendly clusters
- **25+ years of reliability** — proven infrastructure trusted by companies worldwide

---

## About the Author

I'm Vito Botta, Lead Platform Architect at [Brella](https://www.brella.io/), an event management platform based in Finland. I handle infrastructure, coding, and supporting the development team.

I also spend time as a bug bounty hunter, finding and responsibly reporting security vulnerabilities.

Connect with me at [vitobotta.com](https://vitobotta.com/). I'm available for consultancies around hetzner-k3s and Kubernetes on Hetzner.

---

## Why Sponsor?

This project is maintained by a single developer in my spare time. Sponsorship helps me:

- Respond to issues faster
- Ship new features regularly
- Keep the project compatible with new Hetzner Cloud updates

If hetzner-k3s saves you time or money, please consider [supporting its development](https://github.com/sponsors/vitobotta).

### Platinum Sponsors

A huge thank you to <a href="https://alamos.gmbh">Alamos GmbH</a> for sponsoring the development of awesome features!

<a href="https://alamos.gmbh"><img src="Alamos_black.svg" alt="Alamos" height="80"></a>

### Backers

Also thanks to [@deubert-it](https://github.com/deubert-it), [@jonasbadstuebner](https://github.com/jonasbadstuebner), [@ricristian
](https://github.com/ricristian), [@QuentinFAIDIDE](https://github.com/QuentinFAIDIDE) for their support!


---

## Code of Conduct

Everyone interacting in the hetzner-k3s project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/vitobotta/hetzner-k3s/blob/main/CODE_OF_CONDUCT.md).

---

## License

This tool is available as open source under the terms of the [MIT License](https://github.com/vitobotta/hetzner-k3s/blob/main/LICENSE.txt).
