# Troubleshooting

If the tool stops working after creating instances and you experience timeouts, the issue might be related to your SSH key. This can happen if you’re using a key with a passphrase or an older key, as newer operating systems may no longer support certain encryption methods.

To fix this, you can try enabling `networking`.`ssh`.`use_agent` by setting it to `true`. This lets the SSH agent manage the key. If you’re not familiar with what an SSH agent does, you can refer to [this page](https://smallstep.com/blog/ssh-agent-explained/) for a straightforward explanation.

You can also run `hetzner-k3s` with the `DEBUG` environment variable set to `true`. This will provide more detailed output, which can help you identify the root of the problem.

In most cases, if you’re able to manually run `ssh` commands on the servers using a specific keypair, `hetzner-k3s` should work as well, since it relies on the `ssh` binary to function.
