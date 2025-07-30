# Storage

hetzner-k3s provides integrated storage solutions for your Kubernetes workloads. The Hetzner CSI Driver is automatically installed during cluster creation, enabling seamless integration with Hetzner's block storage services.

## Overview

Two storage classes are available:

1. **`hcloud-volumes`** (default): Uses Hetzner's block storage based on Ceph, providing replicated and highly available storage
2. **`local-path`**: Uses local node storage for maximum IOPS performance (disabled by default)

## Hetzner Block Storage (hcloud-volumes)

### Features

- **Replicated**: Based on Ceph, ensuring data is replicated across multiple disks
- **Highly Available**: Redundant storage with no single point of failure
- **Minimum Size**: 10Gi (smaller requests will be automatically rounded up)
- **Maximum Size**: 10Ti per volume
- **Dynamic Provisioning**: Volumes are automatically created and attached when needed

### Basic Usage

Create a Persistent Volume Claim (PVC) using the default storage class:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

This will automatically provision a 10Gi Hetzner volume and attach it to the pod that uses this PVC.

### Example: WordPress with Persistent Storage

```yaml
---
# Persistent Volume Claim for WordPress
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wordpress-pvc
  labels:
    app: wordpress
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
# Persistent Volume Claim for MySQL
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
  labels:
    app: mysql
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
# MySQL Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  labels:
    app: mysql
spec:
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "rootpassword"
        - name: MYSQL_DATABASE
          value: "wordpress"
        - name: MYSQL_USER
          value: "wordpress"
        - name: MYSQL_PASSWORD
          value: "wordpress"
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: mysql-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-storage
        persistentVolumeClaim:
          claimName: mysql-pvc
---
# WordPress Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - name: wordpress
        image: wordpress:latest
        env:
        - name: WORDPRESS_DB_HOST
          value: "mysql"
        - name: WORDPRESS_DB_USER
          value: "wordpress"
        - name: WORDPRESS_DB_PASSWORD
          value: "wordpress"
        - name: WORDPRESS_DB_NAME
          value: "wordpress"
        ports:
        - containerPort: 80
        volumeMounts:
        - name: wordpress-storage
          mountPath: /var/www/html
      volumes:
      - name: wordpress-storage
        persistentVolumeClaim:
          claimName: wordpress-pvc
```

## Local Path Storage

### Overview

The Local Path storage class uses the node's local disk storage directly, providing higher IOPS and lower latency compared to network-attached storage. This is ideal for:

- High-performance databases (Redis, MongoDB, PostgreSQL)
- Caching systems
- Temporary storage
- Applications requiring maximum storage performance

### Enabling Local Path Storage

To enable the `local-path` storage class, add this to your cluster configuration:

```yaml
local_path_storage_class:
  enabled: true
```

### Usage Example

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-cache-pvc
spec:
  storageClassName: local-path
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
spec:
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:alpine
        ports:
        - containerPort: 6379
        volumeMounts:
        - name: redis-data
          mountPath: /data
      volumes:
      - name: redis-data
        persistentVolumeClaim:
          claimName: redis-cache-pvc
```

### Important Considerations

**Advantages of Local Path Storage:**
- **Higher Performance**: No network overhead, direct disk access
- **Lower Latency**: Faster read/write operations
- **Reduced Cost**: No additional costs for network storage

**Limitations of Local Path Storage:**
- **Not Highly Available**: Data is tied to specific nodes
- **No Replication**: Data loss occurs if node fails, so it works best when the application takes care of replication already
- **Limited to Single Node**: Pod can only be scheduled on the node where data resides
- **Manual Migration**: Data must be manually migrated when moving pods

## Storage Class Comparison

| Feature | hcloud-volumes | local-path |
|---------|----------------|------------|
| **High Availability** | ✅ Yes | ❌ No |
| **Data Replication** | ✅ Yes | ❌ No |
| **Performance** | Good (Network) | Excellent (Local) |
| **Maximum Size** | 10Ti | Limited by node disk |
| **Cost** | Volume pricing | Included in instance |
| **Use Case** | Persistent data | Caching, temporary data, high-performance apps |
| **Pod Migration** | ✅ Easy | ❌ Manual |

## Advanced Storage Features

### Volume Expansion

You can expand existing volumes online without downtime:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-expandable-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

To expand the volume:

```bash
# Edit the PVC to increase the size
kubectl edit pvc my-expandable-pvc

# Change storage: 10Gi to storage: 20Gi
```

The CSI driver will automatically resize the filesystem if supported.

## Storage Best Practices

### 1. Choose the Right Storage Type

- **Use `hcloud-volumes` for:**
  - Production databases
  - Persistent application data
  - Content that must survive pod restarts
  - Applications requiring high availability

- **Use `local-path` for:**
  - Caching layers (Redis, Memcached) and databases (Postgres, MySQL)
  - Temporary file storage
  - High-performance computing workloads
  - Applications that can tolerate data loss

### 2. Monitor Storage Usage

```bash
# Check PVC usage
kubectl get pvc -A
kubectl describe pvc <pvc-name>

# Check actual disk usage on nodes
kubectl get nodes -o wide
ssh root@<node-ip> 'df -h'
```

### 3. Set Resource Limits

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: monitored-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
    # Optional: Set resource limits (enforced by storage class)
    limits:
      storage: 20Gi
```

### 4. Use Storage Classes Appropriately

```yaml
# Explicitly specify storage class
spec:
  storageClassName: hcloud-volumes  # or local-path
```

### 5. Implement Backup Strategies

- **Application-level Backups**: Implement regular backups using tools like velero, restic, or application-specific backup solutions
- **Off-server Backups**: Ensure critical data is backed up to external storage or cloud storage
- **Monitoring**: Set up alerts for storage usage and disk space

## Troubleshooting Storage Issues

### PVC Stuck in Pending

1. **Check Storage Class**:
   ```bash
   kubectl get sc
   ```

2. **Verify PVC Definition**:
   ```bash
   kubectl describe pvc <pvc-name>
   ```

3. **Check CSI Driver Status**:
   ```bash
   kubectl get pods -n kube-system | grep csi
   kubectl logs -n kube-system <csi-pod-name>
   ```

### Volume Mount Failures

1. **Check Volume Attachment**:
   ```bash
   kubectl get pv
   kubectl describe pv <pv-name>
   ```

2. **Verify Pod Definition**:
   ```bash
   kubectl describe pod <pod-name>
   ```

3. **Check Node Capacity**:
   ```bash
   kubectl describe node <node-name>
   ```

### Performance Issues

1. **Monitor I/O**:
   ```bash
   kubectl exec -it <pod-name> -- iostat -x 1
   ```

2. **Check Storage Type**: Ensure you're using the right storage class for your workload

3. **Consider Local Storage**: For high-performance workloads, consider switching to `local-path`

## Cost Optimization

### hcloud-volumes Costs

- **Monthly Charge**: Based on volume size (€0.04/GB per month)

### Optimization Strategies

1. **Right-size Volumes**: Start with smaller sizes and expand as needed
2. **Use Local Storage**: For temporary or high-performance data
3. **Monitor Usage**: Identify and reclaim unused storage

### Monitoring Commands

```bash
# Check storage usage across all namespaces
kubectl get pvc -A --no-headers | awk '{print $4, $5}'

# List all storage classes
kubectl get sc

# Check CSI driver pods
kubectl get pods -n kube-system | grep -E '(csi|storage)'

# Check volume health
kubectl get pv -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CAPACITY:.spec.capacity.storage,STORAGE-CLASS:.spec.storageClassName
```
