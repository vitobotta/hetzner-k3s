# Troubleshooting

If the tool hangs forever after creating instances and you see timeouts, this may be caused by problems with your SSH key, for example if you use a key with a passphrase or an older key (due to the deprecation of some crypto stuff in newwer operating systems). In this case you may want to try setting `use_ssh_agent` to `true` to use the SSH agent. If you are not familiar with what an SSH agent is, take a look at [this page](https://smallstep.com/blog/ssh-agent-explained/) for an explanation.
