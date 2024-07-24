## Prerequisites

All that is needed to use this tool is

- an Hetzner Cloud account

- an Hetzner Cloud token: for this you need to create a project from the cloud console, and then an API token with **both read and write permissions** (sidebar > Security > API Tokens); you will see the token only once, so be sure to take note of it somewhere safe

- kubectl and Helm installed

___
# Installation

Before using the tool, be sure to have kubectl installed as it's required to install some components in the cluster and perform k3s upgrades.

### macOS

#### With Homebrew

```bash
brew install vitobotta/tap/hetzner_k3s
```

#### Binary installation

You need to install these dependencies first:
- libssh2
- libevent
- bdw-gc
- libyaml
- pcre
- gmp

##### Intel

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v1.1.5/hetzner-k3s-macos-amd64
chmod +x hetzner-k3s-macos-amd64
sudo mv hetzner-k3s-macos-amd64 /usr/local/bin/hetzner-k3s
```

##### Apple Silicon / M1

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v1.1.5/hetzner-k3s-macos-arm64
chmod +x hetzner-k3s-macos-arm64
sudo mv hetzner-k3s-macos-arm64 /usr/local/bin/hetzner-k3s
```

### Linux

#### amd64

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v1.1.5/hetzner-k3s-linux-amd64
chmod +x hetzner-k3s-linux-amd64
sudo mv hetzner-k3s-linux-amd64 /usr/local/bin/hetzner-k3s
```

#### arm

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v1.1.5/hetzner-k3s-linux-arm64
chmod +x hetzner-k3s-linux-arm64
sudo mv hetzner-k3s-linux-arm64 /usr/local/bin/hetzner-k3s
```

### Windows

I recommend using the Linux binary under [WSL](https://learn.microsoft.com/en-us/windows/wsl/install).


### Limitations:

- if possible, please use modern SSH keys since some operating systems have deprecated old crypto based on SHA1; therefore I recommend you use ECDSA keys instead of the old RSA type
- if you use a snapshot instead of one of the default images, the creation of the instances will take longer than when using a regular image
- the setting `api_allowed_networks` allows specifying which networks can access the Kubernetes API, but this only works with single master clusters currently. Multi-master HA clusters require a load balancer for the API, but load balancers are not yet covered by Hetzner's firewalls
- if you enable autoscaling for one or more nodepools, do not change that setting afterwards as it can cause problems to the autoscaler
- autoscaling is only supported when using Ubuntu or one of the other default images, not snapshots
- worker nodes created by the autoscaler must be deleted manually from the Hetzner Console when deleting the cluster (this will be addressed in a future update)
- SSH keys with passphrases can only be used if you set `use_ssh_agent` to `true` and use an SSH agent to access your key. To start and agent e.g. on macOS:

```bash
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/<private key>
```

