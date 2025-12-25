# Resizing root partition with additional post k3s commands

When deploying storage solutions like Rook Ceph, you may need to resize the root partition to free up disk space for use by the storage system. This guide shows you how to use the `additional_post_k3s_commands` setting to automate this process.

## Overview

By default, Hetzner Cloud instances automatically expand the root partition to use the entire available disk space. To manually manage partitions (e.g., for Rook Ceph storage), you need to disable this automatic behavior and then use custom commands to resize partitions according to your needs.

The following commands will:

1. Expand the GPT partition table to use the entire disk
2. Resize the root partition to use 50% of the disk
3. Create a new partition using the remaining space
4. Expand the filesystem to use the entire root partition

## Prerequisites

Disable automatic root partition growth by setting `grow_root_partition_automatically` to `false`. You can set this globally for all nodes or override it per node pool.

### Global Setting

Apply to all nodes in the cluster:

```yaml
grow_root_partition_automatically: false
```

### Per Node Pool Override

Configure different partitioning strategies per node pool:

```yaml
worker_node_pools:
- name: storage-workers
  instance_type: cpx32
  location: fsn1
  grow_root_partition_automatically: false  # Disable for storage nodes
  additional_post_k3s_commands:
  - [ sgdisk, -e, /dev/sda ]
  - [ partprobe ]
  - [ parted, -s, /dev/sda, mkpart, primary, ext4, "50%", "100%" ]
  - [ growpart, /dev/sda, "1" ]
  - [ resize2fs, /dev/sda1 ]

- name: regular-workers
  instance_type: cpx22
  location: hel1
  # Inherits global setting (or true if global is not set)
  # grow_root_partition_automatically: true  # automatic growth
```

**How it works:**
- Global setting defaults to `true` (automatic growth)
- Per-pool setting overrides global setting
- If not specified per pool, inherits global setting
- When `false`, creates `/etc/growroot-disabled` to prevent automatic growth

## Partition Commands

Add these `additional_post_k3s_commands` to disable automatic growth and manually resize partitions:

```yaml
additional_post_k3s_commands:
- [ sgdisk, -e, /dev/sda ]
- [ partprobe ]
- [ parted, -s, /dev/sda, mkpart, primary, ext4, "50%", "100%" ]
- [ growpart, /dev/sda, "1" ]
- [ resize2fs, /dev/sda1 ]
```

### Command Breakdown

1. **`[ sgdisk, -e, /dev/sda ]`**
   - Expands the GPT partition table to use the entire disk space

2. **`[ partprobe ]`**
   - Notifies the kernel of partition table changes

3. **`[ parted, -s, /dev/sda, mkpart, primary, ext4, "50%", "100%" ]`**
   - Creates a new partition using the remaining 50% of disk space
   - Available for Rook Ceph or other storage solutions

4. **`[ growpart, /dev/sda, "1" ]`**
   - Resizes root partition (partition 1) to use 50% of the disk

5. **`[ resize2fs, /dev/sda1 ]`**
   - Expands the ext4 filesystem to use the entire root partition

## Result

After running these commands:

- Root partition (`/dev/sda1`) uses 50% of disk space
- New partition available for storage solutions like Rook Ceph
- Filesystem expanded to use entire root partition

## Important Notes

- **Device Names**: Commands assume root disk is `/dev/sda` and root partition is `/dev/sda1`. Adjust if needed.
- **Test First**: Test on a non-critical node before production use.
- **Backup Data**: These commands are destructive. Backup important data before applying.
- **Root Privileges**: Commands run as root, which is standard for `additional_post_k3s_commands`.

## Example Configuration

Complete cluster configuration with disk resizing for storage nodes:

```yaml
grow_root_partition_automatically: true  # Default for most nodes

masters_pool:
  instance_type: cpx22
  instance_count: 3
  locations: [fsn1, hel1, nbg1]
  # Inherits global: true (automatic growth)

worker_node_pools:
- name: storage-workers
  instance_type: cpx32
  instance_count: 4
  location: fsn1
  grow_root_partition_automatically: false  # Override: manual partitioning
  additional_post_k3s_commands:
  - [ sgdisk, -e, /dev/sda ]
  - [ partprobe ]
  - [ parted, -s, /dev/sda, mkpart, primary, ext4, "50%", "100%" ]
  - [ growpart, /dev/sda, "1" ]
  - [ resize2fs, /dev/sda1 ]

- name: regular-workers
  instance_type: cpx22
  instance_count: 2
  location: hel1
  # Inherits global: true (automatic growth)

# Other cluster settings...
```

This setup gives you flexibility: regular nodes use automatic growth while storage nodes use custom partitioning optimized for Rook Ceph or similar storage solutions.
