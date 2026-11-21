# etcd Snapshots and Restore

With `datastore.mode: etcd`, which is the default, all of the cluster state lives in the embedded etcd database that runs on the master nodes. hetzner-k3s configures scheduled etcd snapshots on every master, optionally copies them to an S3 compatible bucket, and leaves restoring to k3s itself.

This page covers how the snapshots are configured, how to find one, and how to restore from it: from a local file, from S3, on a single master cluster and on a cluster with several masters.

## How snapshots are configured

hetzner-k3s passes two snapshot flags to every master unless you change them:

- `--etcd-snapshot-schedule-cron='0 * * * *'`: one snapshot per hour, per master
- `--etcd-snapshot-retention=24`: the 24 most recent ones are kept

```yaml
datastore:
  mode: etcd
  etcd:
    snapshot_retention: 24
    snapshot_schedule_cron: "0 * * * *"
```

Every master writes its own snapshots and keeps its own retention window, so a three master cluster has three sets of files, each with the name of the node in the filename (`etcd-snapshot-<cluster-name>-master1-1753178523` for example).

To copy the snapshots off the cluster, enable S3:

```yaml
datastore:
  mode: etcd
  etcd:
    snapshot_retention: 24
    snapshot_schedule_cron: "0 * * * *"
    s3_enabled: true
    s3_endpoint: "s3.eu-central-1.amazonaws.com" # hostname, without https://
    s3_region: "eu-central-1"
    s3_bucket: "my-etcd-backups"
    s3_folder: "production" # optional
    s3_access_key: "..."
    s3_secret_key: "..."
    s3_force_path_style: false # set to true for MinIO and similar
```

The credentials can also come from the `ETCD_S3_ACCESS_KEY` and `ETCD_S3_SECRET_KEY` environment variables at the time you run `create`. In that case leave the two keys out of the file. The region, endpoint and bucket have equivalent `ETCD_S3_*` variables.

Run `create` again after changing this section. The masters pick up the new flags on the next start of k3s, which `create` only triggers when the systemd unit actually changed.

Snapshots contain the etcd database together with the cluster CA certificates and keys, encrypted with a key derived from the cluster token. Treat the bucket as sensitive: private access, encryption at rest, and a lifecycle rule that keeps it out of reach of the retention window you actually need.

## Find a snapshot

On a master, over SSH:

```bash
sudo k3s etcd-snapshot list
sudo ls -l /var/lib/rancher/k3s/server/db/snapshots/
```

From any machine with a working kubeconfig, this shows every snapshot on every master at once:

```bash
kubectl get etcdsnapshotfile
```

In the bucket, with any S3 client:

```bash
aws s3 ls s3://my-etcd-backups/production/
```

To take one by hand before a risky change, with a name you will recognise later:

```bash
sudo k3s etcd-snapshot save --name before-upgrade
```

On demand snapshots are not subject to the retention setting, so delete them yourself once they are no longer needed:

```bash
sudo k3s etcd-snapshot delete before-upgrade-<node-name>-<timestamp>
```

## Which flags your cluster actually uses

hetzner-k3s renders the configuration into the systemd unit of k3s, not into `/etc/rancher/k3s/config.yaml`. Every flag it generated for a given master, including the snapshot and S3 settings, is visible there:

```bash
systemctl cat k3s | grep ExecStart
```

That matters for a restore. A `k3s server` command you type by hand reads no config file, so it starts with none of those flags and you pass what the restore needs on the command line. The exception is a cluster where you added a `/etc/rancher/k3s/config.yaml` yourself; k3s reads it, and the next section explains the one place where that changes the command.

## Restore a single master cluster

The snapshot has to be on the master, unless it is in S3.

```bash
# 1. Stop k3s
sudo systemctl stop k3s

# 2. Restore the snapshot and reset the etcd membership
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/etcd-snapshot-my-cluster-master1-1753178523
```

k3s prints `Managed etcd cluster membership has been reset, restart without --cluster-reset flag now.` and exits. It also writes the previous datastore to `/var/lib/rancher/k3s/server/db/etcd-old-<timestamp>/`, so a restore from the wrong snapshot can be repeated with another one.

```bash
# 3. Start k3s normally
sudo systemctl start k3s
```

The unit that `systemctl start` uses is untouched, so the node comes back with the same private IP, the same node name and the same flags as before. Nothing needs to be regenerated: the kubeconfig, the certificates and the API endpoint all come from the snapshot.

## Restore a cluster with several masters

Treat the first master of the cluster, `<cluster-name>-master1`, as the node to restore to. It is the one whose unit carries `--cluster-init`; the other masters join it with `--server https://<master1-private-ip>:6443`. You can confirm which is which with `systemctl cat k3s | grep ExecStart`.

```bash
# 1. Stop k3s on every master
sudo systemctl stop k3s
```

```bash
# 2. On master1 only: restore and reset the membership
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/etcd-snapshot-my-cluster-master1-1753178523
```

```bash
# 3. On master1: start k3s again
sudo systemctl start k3s
```

```bash
# 4. On every other master: drop the old database and start k3s
sudo mv /var/lib/rancher/k3s/server/db /var/lib/rancher/k3s/server/db-old
sudo systemctl start k3s
```

k3s asks for that last step on its own, with `Backup and delete ${datadir}/server/db on each peer etcd server and rejoin the nodes.` Moving the directory instead of deleting it keeps a copy in case the restore has to be reverted; delete it once the cluster is healthy.

The other masters keep their token file, so they rejoin on their own and etcd gets back to three members. The API server is down from step 1 until master1 is listening again at the end of step 3. Leave agents and the load balancer alone, they reconnect by themselves once the API comes back.

## Restore from S3

Pass the S3 flags and give only the snapshot filename as the path, without the bucket or the folder, because those go in their own flags:

```bash
sudo systemctl stop k3s

sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=etcd-snapshot-my-cluster-master1-1753178523 \
  --etcd-s3 \
  --etcd-s3-endpoint=s3.eu-central-1.amazonaws.com \
  --etcd-s3-region=eu-central-1 \
  --etcd-s3-bucket=my-etcd-backups \
  --etcd-s3-folder=production \
  --etcd-s3-access-key=... \
  --etcd-s3-secret-key=...

sudo systemctl start k3s
```

Add `--etcd-s3-bucket-lookup-type=path` for MinIO and other endpoints that need path style, which is the same thing `s3_force_path_style: true` sets, and `--etcd-s3-skip-ssl-verify` for an endpoint with a self-signed certificate. The values are the ones in your configuration file, and `systemctl cat k3s | grep etcd-s3` shows exactly what the cluster was started with.

If the cluster has a `/etc/rancher/k3s/config.yaml` with the S3 settings in it, k3s reads that file too and tries the bucket even when you want a local file. In that case add `--etcd-s3=false` and pass the absolute path to the local snapshot.

Restoring from S3 on an HA cluster follows the same steps as above: the restore runs on master1, and the other masters still need their `db` directory moved away.

## Restore to a different server

The token decrypts the bootstrap data in the snapshot, so restoring on a server that did not take it needs the original one:

```bash
# On any surviving node with the old data, read the token
sudo cat /var/lib/rancher/k3s/server/token
```

Copy the snapshot to the new server, then run the reset on it with `--token`:

```bash
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/etcd-snapshot-my-cluster-master1-1753178523 \
  --token=<token-from-the-old-node>
```

The other masters join it through the address in their own unit, so a replacement master1 has to answer on the private IP they point at. Check the `--server` value in their `/etc/systemd/system/k3s.service` before starting them, and adjust it if `hetzner-k3s create` gave the new instance a different address.

## After the restore

```bash
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get etcdsnapshotfile
```

On each master, check that etcd is healthy again and back to three members:

```bash
sudo apt-get install -y etcd-client
export ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt
export ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt
export ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key
etcdctl member list
etcdctl endpoint health
```

`/var/lib/rancher/k3s/server/db/reset-flag` is written by k3s during a reset to stop a second reset from running by accident, and is removed on the next normal start. If it is still there, the service did not come back up cleanly and the k3s journal is the place to look.

The masters keep taking snapshots on the configured schedule after the restart. There is no need to run `hetzner-k3s create` after a restore: the systemd units were never changed.

## Notes and caveats

- A newer k3s minor version can restore an older snapshot, but a snapshot from a newer version cannot be restored on an older k3s. Pick the snapshot with the release you upgrade to in mind.
- With a private network, which is the default, the nodes have a public and a private address and the systemd unit pins the private one with `--node-ip` and `--advertise-address`. A command typed by hand does not inherit those, so if the node comes up on the wrong address, add `--node-ip=<private-ip>` to the reset command. The private address is in the `ExecStart` line of the unit.
- Snapshots are per node. A snapshot on master2 restores cluster state just as well as one on master1, with the only difference that master1 is the node the others join.
- Snapshots only cover etcd. Volumes, Hetzner Cloud volume data and anything stored outside Kubernetes are not in them and need their own backup.
- `delete` removes the cluster and the network. A snapshot you restored a cluster from is not a substitute for one: keep the S3 bucket outside the lifecycle of the cluster.

## Why there is no `hetzner-k3s restore` command

A restore is the two commands shown above, and the only thing a wrapper could add is filling in the S3 flags from the configuration file. Since those values are already in the systemd unit and readable with `systemctl cat k3s`, a dedicated command would add a second code path for a rare, high risk operation without removing a step. The decision is recorded in [#659](https://github.com/vitobotta/hetzner-k3s/issues/659).
