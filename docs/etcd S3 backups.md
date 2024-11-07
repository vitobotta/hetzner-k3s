### etcd S3 Backups

S3 backups can be enabled for the embedded etcd mode only. You can see the explainations for each option in the [K3s docs](https://docs.k3s.io/cli/etcd-snapshot).

A backup is created for each server instance. If you run your cluster in high availability mode you may want to update the retention value to be how many master instances you have multiplied by how many backups you want for each master. For example if you have 3 masters and you want 3 backups per master you would set retention to 9. The default is 5, so when running 3 master instances, one instance will only have 1 backup.

> "In addition to backing up the datastore itself, you must also back up the server token file at /var/lib/rancher/k3s/server/token. You must restore this file, or pass its value into the --token option, when restoring from backup. If you do not use the same token value when restoring, the snapshot will be unusable, as the token is used to encrypt confidential data within the datastore itself." [K3S Backup/Restore Docs](https://docs.k3s.io/datastore/backup-restore)

You can save the server token file to disk by setting the `token_path` value in your cluster_config.yaml:

```yaml
token_path: "./token"
```
