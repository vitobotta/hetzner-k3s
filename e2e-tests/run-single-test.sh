#!/bin/sh
set -eu
set -o pipefail
. ./env # this env file should set HCLOUD_TOKEN, and perhaps LOCATION and HK3S
HK3S=${HK3S-hetzner-k3s}
CONFIG=$1
shift
HASH=$({
  echo "---"
  echo "$@"
  echo "---"
  cat "$CONFIG"
  } | sha256sum | cut -c1-8)
export NAME="test-$HASH"
OUTDIR="$NAME"
export LOCATION=${LOCATION-ash}
export KUBECONFIG="$OUTDIR/kubeconfig"
export "$@"
if [ -d "$OUTDIR" ]; then
  echo "Output directory '$OUTDIR' already exists."
  echo "Remove or rename it if you want to run that test again."
  exit 1
fi
echo "Creating output directory: $OUTDIR"
mkdir -p "$OUTDIR"
envsubst < "$CONFIG" > "$OUTDIR/config.yaml"
echo "$*" > "$OUTDIR/args"
echo "$CONFIG" > "$OUTDIR/config"

if ! [ -f sshkey ]; then
  ssh-keygen -f sshkey -t ed25519 -N ""
fi

echo "pending" > "$OUTDIR/result"
echo "creating" > "$OUTDIR/status"
if timeout 5m "$HK3S" create --config "$OUTDIR/config.yaml" | tee "$OUTDIR/create.log" 2>&1 ; then
(
  echo "testing" > "$OUTDIR/status"
  set +x -e
  kubectl get nodes -o wide
  kubectl create deployment blue --image jpetazzo/color
  kubectl expose deployment blue --port 80
  kubectl wait deployment blue --for=condition=Available
  kubectl run --rm -it --restart=Never --image curlimages/curl curl http://blue
  echo "ok" > "$OUTDIR/result"
) | tee "$OUTDIR/kubectl.log" 2>&1 || true
fi
echo "deleting" > "$OUTDIR/status"
timeout 5m "$HK3S" delete --config "$OUTDIR/config.yaml" | tee "$OUTDIR/delete.log" 2>&1
if ! grep -qw ok "$OUTDIR/result"; then
  echo "error" > "$OUTDIR/result"
fi
echo "done" > "$OUTDIR/status"

