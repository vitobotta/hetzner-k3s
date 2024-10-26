### etcd S3 Backups

S3 backups can be enabled for the embedded etcd mode only. You can see the explainations for each option in the [K3s docs](https://docs.k3s.io/cli/etcd-snapshot).

> "In addition to backing up the datastore itself, you must also back up the server token file at /var/lib/rancher/k3s/server/token. You must restore this file, or pass its value into the --token option, when restoring from backup. If you do not use the same token value when restoring, the snapshot will be unusable, as the token is used to encrypt confidential data within the datastore itself." [K3S Backup/Restore Docs](https://docs.k3s.io/datastore/backup-restore)
