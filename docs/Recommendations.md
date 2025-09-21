# Recommendations

This page provides best practices and recommendations for different cluster sizes and use cases with hetzner-k3s.

## Small to Medium Clusters (1-50 nodes)

The default configuration works well for small to medium-sized clusters, providing a simple, reliable setup with minimal configuration required.

### Key Considerations
- **Private Network**: Enabled by default for better security
- **CNI**: Flannel for simplicity or Cilium for advanced features
- **Storage**: `hcloud-volumes` for persistence
- **Load Balancers**: Hetzner Load Balancers for production workloads
- **High Availability**: 3 master nodes for production clusters

### Recommended Configuration

```yaml
hetzner_token: <your token>
cluster_name: my-cluster
kubeconfig_path: "./kubeconfig"
k3s_version: v1.32.0+k3s1

networking:
  ssh:
    port: 22
    use_agent: false
    public_key_path: "~/.ssh/id_ed25519.pub"
    private_key_path: "~/.ssh/id_ed25519"
  allowed_networks:
    ssh:
      - 0.0.0.0/0
    api:
      - 10.0.0.0/16  # Restrict to private network
  public_network:
    ipv4: true
    ipv6: true
  private_network:
    enabled: true
    subnet: 10.0.0.0/16
  cni:
    enabled: true
    encryption: false
    mode: flannel

masters_pool:
  instance_type: cpx21
  instance_count: 3  # For HA
  locations:
    - nbg1

worker_node_pools:
- name: workers
  instance_type: cpx31
  instance_count: 3
  location: nbg1
  autoscaling:
    enabled: true
    min_instances: 1
    max_instances: 5

protect_against_deletion: true
create_load_balancer_for_the_kubernetes_api: true
```

## Large Clusters (50+ nodes)

For larger clusters, the default setup has some limitations that need to be addressed.

### Limitations of Default Setup

Hetzner's private networks, used in hetzner-k3s' default configuration, only support up to 100 nodes. If your cluster is going to grow beyond that, you need to disable the private network in your configuration.

### Large Cluster Architecture (Since v2.2.8)

Support for large clusters has significantly improved since version 2.2.8. The main changes include:

1. **Custom Firewall**: Instead of using Hetzner's firewall (which is slow to update), a custom firewall solution was implemented
2. **IP Query Server**: A simple container that checks the Hetzner API every 30 seconds to get the list of all node IPs
3. **Automatic Updates**: Firewall rules are automatically updated without manual intervention

### Setting Up Large Clusters

#### Step 1: Set Up IP Query Server

The IP query server runs as a simple container. You can easily set it up on any Docker-enabled server using the `docker-compose.yml` file in the `ip-query-server` folder of this repository.

```yaml
# docker-compose.yml
version: '3.8'
services:
  ip-query-server:
    build: ./ip-query-server
    ports:
      - "8080:80"
    environment:
      - HETZNER_TOKEN=your_token_here
  caddy:
    image: caddy:2
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
    depends_on:
      - ip-query-server
```

Replace `example.com` in the Caddyfile with your actual domain name and `mail@example.com` with your email address for Let's Encrypt certificates.

#### Step 2: Update Cluster Configuration

```yaml
hetzner_token: <your token>
cluster_name: large-cluster
kubeconfig_path: "./kubeconfig"
k3s_version: v1.32.0+k3s1

networking:
  ssh:
    port: 22
    use_agent: true  # Recommended for large clusters
    public_key_path: "~/.ssh/id_ed25519.pub"
    private_key_path: "~/.ssh/id_ed25519"
  allowed_networks:
    ssh:
      - 0.0.0.0/0  # Required for public network access
    api:
      - 0.0.0.0/0  # Required when private network is disabled
  public_network:
    ipv4: true
    ipv6: true
    # Use custom IP query server for large clusters
    hetzner_ips_query_server_url: https://ip-query.example.com
    use_local_firewall: true  # Enable custom firewall
  private_network:
    enabled: false  # Disable private network for >100 nodes
  cni:
    enabled: true
    encryption: true  # Enable encryption for public network
    mode: cilium  # Better for large scale deployments

# Larger cluster CIDR ranges
cluster_cidr: 10.244.0.0/15  # Larger range for more pods
service_cidr: 10.96.0.0/16   # Larger range for more services
cluster_dns: 10.96.0.10

datastore:
  mode: etcd  # or external for very large clusters
  # external_datastore_endpoint: postgres://...

masters_pool:
  instance_type: cpx31
  instance_count: 3
  locations:
    - nbg1
    - hel1
    - fsn1

worker_node_pools:
- name: compute
  instance_type: cpx41
  location: nbg1
  autoscaling:
    enabled: true
    min_instances: 5
    max_instances: 50
- name: storage
  instance_type: cpx51
  location: hel1
  autoscaling:
    enabled: true
    min_instances: 3
    max_instances: 20

addons:
  embedded_registry_mirror:
    enabled: true  # Recommended for large clusters

protect_against_deletion: true
create_load_balancer_for_the_kubernetes_api: true
k3s_upgrade_concurrency: 2  # Can upgrade more nodes simultaneously
```

### Additional Large Cluster Considerations

#### Network Configuration
- **CIDR Sizing**: Use larger cluster and service CIDR ranges to accommodate more pods and services
- **Encryption**: Enable CNI encryption when using public networks
- **Firewall**: The custom firewall automatically manages allowed IPs without opening ports to the public

#### High Availability Setup
For production large clusters, consider:

1. **Multiple IP Query Servers**: Set up 2-3 instances behind a load balancer for better availability
2. **External Datastore**: Use PostgreSQL instead of etcd for better scalability
3. **Distributed Master Nodes**: Place masters in different locations
4. **Multiple Node Pools**: Different instance types for different workloads

## Cluster Sizing Guidelines

### Development/Tiny Clusters (< 5 nodes)
```yaml
masters_pool:
  instance_type: cpx11
  instance_count: 1  # Single master for testing
worker_node_pools:
- name: workers
  instance_type: cpx11
  instance_count: 1
```

### Small Production Clusters (5-20 nodes)
```yaml
masters_pool:
  instance_type: cpx21
  instance_count: 3  # HA masters
  locations:
    - fsn1
    - hel1
    - nbg1
worker_node_pools:
- name: workers
  instance_type: cpx31
  instance_count: 3
  autoscaling:
    enabled: true
    min_instances: 1
    max_instances: 5
```

### Medium Production Clusters (20-50 nodes)
```yaml
masters_pool:
  instance_type: cpx31
  instance_count: 3
  locations:
    - fsn1
    - hel1
    - nbg1
worker_node_pools:
- name: web
  instance_type: cpx31
  location: nbg1
  autoscaling:
    enabled: true
    min_instances: 3
    max_instances: 10
- name: backend
  instance_type: cpx41
  location: hel1
  autoscaling:
    enabled: true
    min_instances: 2
    max_instances: 8
```

### Large Production Clusters (50-200+ nodes)
Use the large cluster configuration shown above with:
- Multiple node pools for different workloads
- Custom firewall and IP query server
- Larger instance types for masters
- External datastore if needed

## Performance Optimization

### Embedded Registry Mirror

In v2.0.0, there's a new option to enable the `embedded registry mirror` in k3s. You can find more details [here](https://docs.k3s.io/installation/registry-mirror). This feature uses [Spegel](https://github.com/spegel-org/spegel) to enable peer-to-peer distribution of container images across cluster nodes.

**Benefits:**
- Faster pod startup times
- Reduced external registry calls
- Better reliability when external registries are inaccessible
- Cost savings on egress bandwidth

**Configuration:**
```yaml
embedded_registry_mirror:
  enabled: true
```

> **Note**: Ensure your k3s version supports this feature before enabling.

### Storage Selection

#### Use `hcloud-volumes` for:
- Production databases where the app does not take care of replication already
- Persistent application data
- Content that must survive pod restarts
- Applications requiring high availability

#### Use `local-path` for:
- High-performance caching (Redis, Memcached)
- High-performance databases (Postgres, MySQL) where the app takes care of replication already
- Temporary file storage
- Applications that can tolerate data loss
- Maximum IOPS performance

### CNI Selection

#### Flannel
- **Pros**: Simple, lightweight, good for small clusters
- **Cons**: Limited features, doesn't scale well to very large clusters
- **Best for**: Small to medium clusters, simplicity

#### Cilium
- **Pros**: Advanced features, better performance scales well
- **Cons**: More complex setup, higher resource usage
- **Best for**: Medium to large clusters, advanced networking needs

## Security Recommendations

### Network Security
1. **Restrict SSH and API Access**: Use CIDR restrictions in `allowed_networks.api` and `allowed_networks.ssh`
2. **Use Private Networks**: When possible, use private networks for cluster communication
3. **Monitor Network Traffic**: Implement network policies and monitoring

### SSH Security
1. **Use SSH Keys**: hetzner-k3s configures nodes with SSH keys by default
2. **SSH Agent**: Enable `use_agent: true` for passphrase-protected keys
3. **Key Rotation**: Regularly rotate SSH keys if needed
4. **Access Logs**: Monitor SSH access logs

### Cluster Security
1. **RBAC**: Implement proper role-based access control
2. **Network Policies**: Use Kubernetes network policies
3. **Pod Security**: Implement pod security standards
4. **Regular Updates**: Keep k3s and components updated

## Cost Optimization

### Instance Selection
- **Right-size Instances**: Start smaller and scale up as needed
- **Use Autoscaling**: Only pay for what you use

### Storage Optimization
- **Clean Up Volumes**: Regularly delete unused volumes
- **Use Local Storage**: For temporary data where appropriate
- **Monitor Usage**: Set up monitoring to identify unused storage

### Network Optimization
- **Use Private Networks**: Reduce egress costs
- **Optimize Images**: Use smaller container images
- **Registry Mirror**: Reduce registry egress costs

## Monitoring and Observability

### Essential Monitoring
1. **Node Resources**: CPU, memory, disk usage
2. **Cluster Health**: Node readiness, pod status
3. **Network Traffic**: Bandwidth usage, connection counts
4. **Storage Performance**: I/O operations, latency

### Recommended Tools
- **Prometheus + Grafana**: For metrics and dashboards
- **Loki**: For log aggregation
- **Alertmanager**: For alerting
- **Node Exporter**: For node metrics
