#!/bin/bash

# Get a list of namespaces
namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

# Iterate over each namespace
for ns in $namespaces; do
  # Get a list of pod names in the current namespace
  pod_names=$(kubectl get pods -n "$ns" --field-selector='status.phase!=Running,status.phase!=Succeeded,status.phase!=Failed' --output=jsonpath='{.items[*].metadata.name}')

  # Get a list of pod names in CrashLoopBackOff state
  crashloopbackoff_pods=$(kubectl get pods -n "$ns" --field-selector='status.phase=Running' --output=jsonpath='{.items[?(.status.containerStatuses[].restartCount>0)].metadata.name}')

  # Delete each pod in the current namespace
  for pod in $pod_names $crashloopbackoff_pods; do
    kubectl delete pod "$pod" -n "$ns"
  done
done
