# Why hetzner-k3s Stands Out

There are several ways to run Kubernetes on Hetzner Cloud. This page explains why hetzner-k3s might be the right choice for your needs, with an honest look at how it compares to alternatives.

---

## At a Glance

| Factor | hetzner-k3s | Managed Services | Terraform-based | Cluster API |
|--------|-------------|------------------|-----------------|-------------|
| **Setup time** | 2-3 minutes | 5-10 minutes | 15-30+ minutes | 20+ minutes |
| **Dependencies** | CLI only | Account signup | Terraform, Packer, HCL | Management cluster |
| **Data privacy** | Full control | Third-party access | Full control | Full control |
| **Monthly cost** | Infrastructure only | Infrastructure + platform fees (scale with cluster size) | Infrastructure only | Infrastructure only |
| **Credential exposure** | None | API tokens to third party | None | None |
| **Learning curve** | Low | Low | Medium-High | High |
| **Best for** | Most Hetzner users | Zero-ops teams | Terraform-native teams | Multi-cloud standardization |

---

## What hetzner-k3s Offers

### Speed

Creating a highly available cluster with 3 masters and 3 workers takes **2-3 minutes**. This includes:

- Provisioning all infrastructure (instances, load balancer, private network, firewall)
- Deploying k3s to all nodes
- Installing Cloud Controller Manager, CSI driver, System Upgrade Controller, and Cluster Autoscaler

In stress testing, a 500-node cluster was created in under 11 minutes.

### Minimal Dependencies

You need exactly three things:

1. A Hetzner Cloud API token
2. An SSH key pair
3. The hetzner-k3s CLI tool

No Terraform, Packer, Ansible, or existing Kubernetes cluster. No need to learn HCL or manage Terraform state.

### Lightweight Kubernetes

k3s uses significantly less memory and CPU than standard Kubernetes, leaving more resources for your workloads. It's a single binary, making deployments and upgrades fast and reliable.

### Full Data Sovereignty

- Run the tool on your own machine
- Your Hetzner API token never leaves your system
- No third party gains access to your clusters, credentials, or data
- Complete control with no intermediary

### Cost Efficiency

- The tool is free and open source
- You only pay for Hetzner infrastructure
- No per-user fees, per-cluster fees, or management fees
- No surprise charges as your team or infrastructure grows

---

## How Alternatives Compare

### Managed Services (Cloudfleet, Edka, Syself)

Managed services handle cluster operations for you, which is valuable if you want zero operational overhead.

#### Considerations

**Credential sharing**: You provide your Hetzner API token to the service. The provider has ongoing access to your cloud account and can see your workloads. For regulated industries or security-conscious teams, this may be a concern.

**Pricing structure**: Managed services typically charge:
- A base cluster management fee
- Per-vCPU fees for worker nodes
- Sometimes per-user fees for enterprise tiers

These platform fees add up quickly as clusters grow. A small development cluster might have modest fees, but production clusters with dozens of nodes can see platform costs that rival or exceed the underlying Hetzner infrastructure costs.

For example, Cloudfleet's free tier limits you to 24 vCPUs with standard availability. Beyond that, costs scale with each additional vCPU. The difference between hetzner-k3s (infrastructure only) and managed services becomes substantial at scale—potentially saving hundreds or thousands of euros per month on larger deployments.

**Vendor dependency**: Your cluster management depends on the service's availability. If the provider changes pricing, terms, or discontinues service, you're affected. Migration requires effort.

**When managed services make sense**: Teams that prioritize zero operational overhead over cost or data privacy. Organizations where someone else handling infrastructure is worth the ongoing fees.

---

### Terraform-based Solutions (terraform-hcloud-kube-hetzner, etc.)

Terraform-based solutions are powerful and flexible, especially for teams already using Terraform.

#### Considerations

**Multiple dependencies**: You need:
- Terraform or OpenTofu
- Packer (for custom images)
- kubectl CLI
- hcloud CLI

Each tool requires installation, configuration, and learning.

**Learning curve**: You need to understand:
- Terraform state management
- HCL syntax
- How changes propagate through Terraform plans
- Debugging across multiple tools

**Ongoing maintenance**: Terraform state must be stored and managed carefully. Upgrades require understanding how Terraform handles infrastructure drift.

**What you gain**: More flexibility, infrastructure-as-code patterns familiar to platform teams, integration with existing Terraform workflows.

**When Terraform-based solutions make sense**: Teams already using Terraform extensively. Organizations with platform engineering teams comfortable with IaC tooling.

---

### Claudie

Claudie is designed for multi-cloud and hybrid deployments. It provisions clusters across different cloud providers from a single management interface.

#### Considerations

**Requires a management cluster**: Claudie runs on an existing Kubernetes cluster. You need Kubernetes to create Kubernetes.

For production use, this management cluster needs to be resilient since Claudie maintains state for all clusters it provisions.

**Significant dependencies**: The management cluster needs:
- cert-manager
- Multiple Claudie components (ansible, builder, claudie-operator, dynamodb, kube-eleven, kuber, minio, mongodb, scheduler, terraformer)

**Operational overhead**: You're responsible for keeping the management cluster healthy. If it has issues, you can't manage your provisioned clusters.

**When Claudie makes sense**: Organizations running clusters across multiple cloud providers who need unified management. Hybrid cloud scenarios where Hetzner is one of several providers.

---

### Talos Linux

Talos is an immutable, secure operating system built specifically for Kubernetes.

#### Considerations

**More complex setup**: Deploying Talos on Hetzner requires:
- Manually creating network components
- Setting up a NAT gateway VM
- Generating Talos-specific configuration files
- Bootstrapping nodes individually

**Different operational model**: Talos has no SSH access and is managed entirely via API. This provides enhanced security but requires adapting your workflows.

**When Talos makes sense**: Organizations prioritizing immutable infrastructure and maximum security. Teams comfortable with the Talos operational model.

---

### Cluster API (CAPH)

Cluster API provides declarative, Kubernetes-style management of cluster infrastructure.

#### Considerations

**Requires a management cluster**: Like Claudie, you need an existing Kubernetes cluster (often a local kind cluster) to provision your workload cluster.

**Steeper learning curve**: Understanding Cluster API concepts and CAPH-specific resources takes time.

**Kubernetes-native approach**: If you're comfortable with Kubernetes operators and CRDs, this model may feel natural.

**When CAPH makes sense**: Organizations standardizing on Cluster API across multiple providers. Teams that want to manage infrastructure with kubectl and GitOps.

---

## Real-World Considerations

### Development and Testing

For quick iteration, hetzner-k3s excels. Creating and destroying clusters in minutes enables:
- Ephemeral test environments
- Rapid prototyping
- Cost-effective experimentation (pay only for what you use)

### Small to Medium Production

Most teams running 1-50 node clusters on Hetzner find hetzner-k3s sufficient. You get:
- High availability with multi-location masters
- Autoscaling for variable workloads
- Zero recurring platform fees

### Large Scale (100+ nodes)

hetzner-k3s has been tested with 500 nodes and is designed to scale beyond. Clusters over 100 nodes require some configuration changes—see the [Recommendations](Recommendations.md) page for setup details.

### Multi-Cloud Requirements

If you need clusters across AWS, GCP, and Hetzner with unified management, consider Claudie or Cluster API. hetzner-k3s is optimized specifically for Hetzner.

---

## The Bottom Line

**hetzner-k3s** is designed for teams who want:

- Production-ready clusters in minutes, not hours
- Complete control over credentials and data
- No ongoing platform fees
- Minimal tooling complexity

It's not the right choice if you:

- Want someone else to handle all operations (consider managed services)
- Need multi-cloud standardization (consider Cluster API or Claudie)
- Already have extensive Terraform infrastructure (consider terraform-hcloud-kube-hetzner)

For most teams running Kubernetes on Hetzner Cloud, hetzner-k3s provides the best balance of speed, simplicity, and control.
