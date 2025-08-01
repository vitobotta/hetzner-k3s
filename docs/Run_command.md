# The 'run' Command

The `hetzner-k3s run` command allows you to execute a single command or an entire script on either all nodes in your cluster or on a specific instance. This is particularly useful for maintenance tasks, configuration updates, and automated operations across your cluster.

## Command Overview

```bash
hetzner-k3s run --config <config-file> [options]
```

## Required Parameters

- `--config`, `-c`: The path to your cluster configuration YAML file

## Execution Modes

### 1. Running Commands

Execute a single command on all cluster nodes:

```bash
hetzner-k3s run --config cluster.yaml --command "sudo apt update && sudo apt upgrade -y"
```

Execute a single command on a specific instance:

```bash
hetzner-k3s run --config cluster.yaml --command "hostname" --instance "worker-node-1"
```

### 2. Running Scripts

Execute a script file on all cluster nodes:

```bash
hetzner-k3s run --config cluster.yaml --script fix-ssh.sh
```

Execute a script file on a specific instance:

```bash
hetzner-k3s run --config cluster.yaml --script fix-ssh.sh --instance "master-node-1"
```

## Option Parameters

- `--command`: The shell command to execute
- `--script`: The path to a script file to execute
- `--instance`: The name of a specific instance to run the command/script on (if not specified, runs on all instances)

**Note**: You must specify exactly one of either `--command` or `--script`.

## Examples

### Example 1: Check system information on all nodes

```bash
hetzner-k3s run --config my-cluster.yaml --command "uname -a && df -h"
```

### Example 2: Update packages on a specific worker node

```bash
hetzner-k3s run --config my-cluster.yaml --command "sudo apt update && sudo apt list --upgradable" --instance worker-1
```

### Example 3: Run the SSH fix script on all nodes

```bash
hetzner-k3s run --config my-cluster.yaml --script fix-ssh.sh
```

### Example 4: Run a custom maintenance script on master node only

```bash
hetzner-k3s run --config my-cluster.yaml --script maintenance.sh --instance master-1
```

## How It Works

### Command Execution

When using `--command`, hetzner-k3s:
1. Connects to each instance via SSH
2. Executes the specified command directly
3. Captures and displays the output
4. Returns the command completion status

### Script Execution

When using `--script`, hetzner-k3s:
1. Validates the script file exists and is readable
2. Uploads the script to `/tmp/<script-name>` on each instance
3. Makes the script executable
4. Executes the script
5. Captures and displays the output
6. Automatically cleans up by removing the uploaded script file

### Parallel Execution

The `run` command executes operations in parallel across all instances, significantly reducing the time required for cluster-wide operations. Each instance's output is displayed separately for clarity.

### User Confirmation

Before execution, the command displays:
- A summary of instances that will be affected
- The command or script to be executed
- A confirmation prompt requiring you to type "continue" to proceed

## Error Handling

The command handles various error scenarios:

- **SSH Connection Issues**: If SSH connection fails, the error is displayed and execution continues on other instances
- **Script File Not Found**: If the specified script file doesn't exist, the command exits with an error
- **Permission Issues**: If the script file is not readable, the command exits with an error
- **Instance Not Found**: If a specific instance name doesn't exist in the cluster, the command exits with an error

## Output Format

Output is organized by instance, making it easy to identify which node produced which output:

```
Found 3 instances in the cluster
Command to execute: hostname

Nodes that will be affected:
  - master-1 (192.168.1.100)
  - worker-1 (192.168.1.101)
  - worker-2 (192.168.1.102)

Type 'continue' to execute this command on all nodes: continue

=== Instance: master-1 (192.168.1.100) ===
master-1
Command completed successfully

=== Instance: worker-1 (192.168.1.101) ===
worker-1
Command completed successfully

=== Instance: worker-2 (192.168.1.102) ===
worker-2
Command completed successfully
```

## Security Considerations

- Commands and scripts are executed with the permissions of the SSH user
- Use `sudo` within commands/scripts when root privileges are required
- Scripts are uploaded to `/tmp/` and executed from there, then automatically cleaned up
- Ensure your script files have appropriate permissions and are secure

## Use Cases

### Maintenance Operations
- System updates: `--command "sudo apt update && sudo apt upgrade -y"`
- Log cleanup: `--command "sudo journalctl --vacuum-time=7d"`
- Service restarts: `--command "sudo systemctl restart docker"`

### Configuration Management
- Apply configuration changes across all nodes
- Deploy configuration files using scripts
- Update system settings

### Troubleshooting
- Check system status: `--command "systemctl status"`
- Examine logs: `--command "journalctl -u k3s-agent -n 50"`
- Verify network connectivity: `--command "ping -c 3 google.com"`

### Security Updates
- Apply security patches cluster-wide
- Update SSH configurations (like the fix-ssh.sh script)
- Modify firewall rules

## Tips and Best Practices

1. **Test on a single instance first**: Use `--instance` to test commands/scripts on one node before applying to all nodes
2. **Use idempotent operations**: Design commands/scripts to be safe to run multiple times
3. **Capture output**: For long-running operations, consider redirecting output to files
4. **Handle errors gracefully**: Include error handling in your scripts when appropriate
5. **Use absolute paths**: In scripts, prefer absolute paths to avoid path-related issues

## Integration with Cluster Operations

The `run` command is particularly powerful when combined with other hetzner-k3s operations:

- Use after cluster creation to apply initial configurations
- Run pre-upgrade checks before upgrading cluster components
- Execute post-upgrade verification commands
- Apply security patches across the entire cluster efficiently