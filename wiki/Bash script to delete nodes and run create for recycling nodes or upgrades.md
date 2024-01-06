```bash
#!/bin/bash

# Check if any arguments are provided
if [ $# -eq 0 ]; then
    echo "No node names provided"
    exit 1
fi

# Iterate over each node name provided as an argument
for node in "$@"
do
    echo "Processing node: $node"

    # Describe the node and extract the ID
    ID=$(kubectl describe node "$node" | grep "ProviderID:" | awk -F'/' '{print $NF}')
    if [ -z "$ID" ]; then
        echo "Failed to extract ID for node $node"
        continue
    fi

    echo "Extracted ID: $ID for node $node"

    # Delete the node using kubectl
    kubectl delete node "$node"
    if [ $? -ne 0 ]; then
        echo "Failed to delete node $node using kubectl"
        continue
    fi

    # Delete the node using the Hetzner Cloud API
    curl -X DELETE \
        -H "Authorization: Bearer $API_TOKEN" \
        "https://api.hetzner.cloud/v1/servers/$ID"

    if [ $? -ne 0 ]; then
        echo "Failed to delete node $node using Hetzner Cloud API"
    else
        echo "Node $node deleted successfully"
    fi
done
```

To use this script:

1. Make sure `kubectl` and `curl` are installed and configured properly on your system.
2. Set the `API_TOKEN` environment variable with your Hetzner Cloud API token.
3. Save this script to a file, for example, `delete_nodes.sh`.
4. Make the script executable: `chmod +x delete_nodes.sh`.
5. Run the script with the names of the nodes you want to delete: `./delete_nodes.sh node1 node2 node3`.
