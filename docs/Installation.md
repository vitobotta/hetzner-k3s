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

##### Intel / x86

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v2.0.8/hetzner-k3s-macos-amd64
chmod +x hetzner-k3s-macos-amd64
sudo mv hetzner-k3s-macos-amd64 /usr/local/bin/hetzner-k3s
```

##### Apple Silicon / ARM

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v2.0.8/hetzner-k3s-macos-arm64
chmod +x hetzner-k3s-macos-arm64
sudo mv hetzner-k3s-macos-arm64 /usr/local/bin/hetzner-k3s
```

### Linux

#### amd64

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v2.0.8/hetzner-k3s-linux-amd64
chmod +x hetzner-k3s-linux-amd64
sudo mv hetzner-k3s-linux-amd64 /usr/local/bin/hetzner-k3s
```

#### arm

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v2.0.8/hetzner-k3s-linux-arm64
chmod +x hetzner-k3s-linux-arm64
sudo mv hetzner-k3s-linux-arm64 /usr/local/bin/hetzner-k3s
```

### Windows

I recommend using the Linux binary under [WSL](https://learn.microsoft.com/en-us/windows/wsl/install).

