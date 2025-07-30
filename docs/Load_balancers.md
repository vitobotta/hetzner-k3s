# Load Balancers

Hetnzer-k3s automatically installs and configures the [Hetzner Cloud Controller Manager](https://github.com/hetznercloud/hcloud-cloud-controller-manager), which enables you to create and manage Hetzner Load Balancers directly from Kubernetes using Services of type `LoadBalancer`.

## Overview

When you create a Service of type `LoadBalancer` in your cluster, the Cloud Controller Manager will automatically:

1. Create a new Hetzner Load Balancer
2. Configure it with the specified settings and annotations
3. Set up health checks for your pods
4. Update the Service status with the Load Balancer's external IP

## Basic Configuration

### Essential Annotations

At a minimum, you'll need these two annotations:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-service
  annotations:
    load-balancer.hetzner.cloud/location: nbg1  # Ensures the load balancer is in the same network zone as your nodes
    load-balancer.hetzner.cloud/use-private-ip: "true"  # Routes traffic between the load balancer and nodes through the private network
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
```

### Recommended Annotations

While the above are essential, I also recommend adding these annotations for production use:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-service
  annotations:
    # Basic configuration
    load-balancer.hetzner.cloud/location: nbg1
    load-balancer.hetzner.cloud/use-private-ip: "true"
    
    # Additional recommended settings
    load-balancer.hetzner.cloud/hostname: app.example.com  # Custom hostname for the load balancer
    load-balancer.hetzner.cloud/name: my-app-lb           # Custom name for the load balancer
    load-balancer.hetzner.cloud/http-redirect-https: 'false'  # Disable HTTP to HTTPS redirect (handled by ingress)
    load-balancer.hetzner.cloud/uses-proxyprotocol: 'true'    # Enable proxy protocol to preserve client IP
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
```

## Advanced Configuration

### Proxy Protocol and Client IP Preservation

The proxy protocol is important because it allows your ingress controller and applications to detect the real client IP address. 

```yaml
annotations:
  load-balancer.hetzner.cloud/uses-proxyprotocol: 'true'
  load-balancer.hetzner.cloud/hostname: app.example.com
```

!!! important "Why use hostname with proxy protocol?"
    Enabling the proxy protocol can cause issues with [cert-manager](https://cert-manager.io/docs/) failing HTTP-01 challenges. To fix this, Hetzner and other providers recommend using a hostname instead of an IP for the load balancer. For more details, read this [explanation](https://github.com/compumike/hairpin-proxy).

### Multiple Services and Ports

You can expose multiple ports and services through the same load balancer:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: multi-port-app
  annotations:
    load-balancer.hetzner.cloud/location: nbg1
    load-balancer.hetzner.cloud/use-private-ip: "true"
    load-balancer.hetzner.cloud/uses-proxyprotocol: 'true'
spec:
  type: LoadBalancer
  selector:
    app: multi-port-app
  ports:
    - protocol: TCP
      name: http
      port: 80
      targetPort: 8080
    - protocol: TCP
      name: https
      port: 443
      targetPort: 8443
```

### Load Balancer Algorithm

You can specify the load balancing algorithm:

```yaml
annotations:
  load-balancer.hetzner.cloud/algorithm: round_robin  # Options: round_robin, least_connections
```

### Health Checks

Customize health check behavior:

```yaml
annotations:
  load-balancer.hetzner.cloud/health-check-interval: "15s"
  load-balancer.hetzner.cloud/health-check-timeout: "10s"
  load-balancer.hetzner.cloud/health-check-retries: "3"
```

## Example: NGINX Ingress Controller

Here's a complete example for deploying NGINX Ingress Controller with a Load Balancer:

```yaml
---
# ingress-nginx-values.yaml
controller:
  kind: DaemonSet
  service:
    annotations:
      # Set the location (must match your node locations)
      load-balancer.hetzner.cloud/location: nbg1
      
      # Load balancer name
      load-balancer.hetzner.cloud/name: nginx-ingress-lb
      
      # Use private network for internal communication
      load-balancer.hetzner.cloud/use-private-ip: "true"
      
      # Enable proxy protocol to preserve client IPs
      load-balancer.hetzner.cloud/uses-proxyprotocol: 'true'
      
      # Set hostname for the load balancer (replace with your domain)
      load-balancer.hetzner.cloud/hostname: ingress.example.com
      
      # Disable automatic HTTP to HTTPS redirect (handled by ingress)
      load-balancer.hetzner.cloud/http-redirect-https: 'false'
```

Install with Helm:

```bash
# Add the Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install ingress-nginx with custom annotations
helm upgrade --install \
  ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  -f ingress-nginx-values.yaml
```

## Available Locations

Hetzner Cloud has data centers in these locations:

| Location Code | City | Country |
|---------------|------|---------|
| `nbg1` | Nuremberg | Germany |
| `fsn1` | Falkenstein | Germany |
| `hel1` | Helsinki | Finland |
| `ash` | Ashburn, VA | USA |
| `hil` | Hillsboro, OR | USA |
| `sin` | Singapore | Singapore |

Make sure to choose a location where your nodes are deployed or across multiple locations if you have a distributed setup.

## Complete List of Annotations

For a full list of available annotations and their descriptions, refer to the [official documentation](https://pkg.go.dev/github.com/hetznercloud/hcloud-cloud-controller-manager/internal/annotation).

Common annotations include:

| Annotation | Description | Default |
|------------|-------------|---------|
| `load-balancer.hetzner.cloud/location` | Location of the load balancer | Required |
| `load-balancer.hetzner.cloud/use-private-ip` | Use private network for node communication | `false` |
| `load-balancer.hetzner.cloud/hostname` | Custom hostname for the load balancer | Auto-generated |
| `load-balancer.hetzner.cloud/name` | Custom name for the load balancer | Service name |
| `load-balancer.hetzner.cloud/uses-proxyprotocol` | Enable proxy protocol | `false` |
| `load-balancer.hetzner.cloud/algorithm` | Load balancing algorithm | `round_robin` |
| `load-balancer.hetzner.cloud/http-redirect-https` | Enable HTTP to HTTPS redirect | `false` |
| `load-balancer.hetzner.cloud/health-check-interval` | Health check interval | `15s` |
| `load-balancer.hetzner.cloud/health-check-timeout` | Health check timeout | `10s` |
| `load-balancer.hetzner.cloud/health-check-retries` | Health check retry count | `3` |

## Troubleshooting

### Load Balancer Stuck in "Pending"

If your load balancer fails to get an external IP:

1. **Check Annotations**: Ensure all required annotations are set correctly
2. **Verify Location**: Make sure the specified location exists and has capacity
3. **Check Logs**: Examine the Cloud Controller Manager logs:
   ```bash
   kubectl logs -n kube-system -l k8s-app=hcloud-cloud-controller-manager
   ```
4. **Check Service**: Verify the Service definition is correct:
   ```bash
   kubectl describe service <service-name>
   ```

### Health Check Failures

If health checks are failing:

1. **Check Pod Status**: Ensure pods are running and ready
2. **Verify Port Mapping**: Confirm the targetPort matches your application port
3. **Check Network Policies**: Ensure no network policies are blocking traffic
4. **Review Pod Logs**: Check application logs for errors

### Connection Issues

If you can't connect through the load balancer:

1. **Check Security Groups**: Verify firewall rules allow traffic
2. **Test Direct Access**: Try accessing pods directly to isolate the issue
3. **Check DNS**: If using a hostname, ensure DNS resolves correctly
4. **Monitor Traffic**: Use `kubectl logs` and `kubectl describe` to trace traffic flow

## Best Practices

1. **Use Private Networks**: Always set `use-private-ip: "true"` for better security and performance
2. **Enable Proxy Protocol**: Use `uses-proxyprotocol: 'true'` to preserve client IP addresses
3. **Choose Right Location**: Place load balancers close to your users for lower latency
4. **Monitor Health**: Regularly check load balancer health and metrics
5. **Use Meaningful Names**: Set custom names for easier identification in the Hetzner console
6. **Configure DNS**: Set up proper DNS records for your load balancer hostnames