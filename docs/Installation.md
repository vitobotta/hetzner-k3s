## Prerequisites

To use this tool, you will need a few things:

- A Hetzner Cloud account.
- A Hetzner Cloud token: To get this, create a project in the cloud console, then generate an API token with **both read and write permissions** (go to the sidebar > Security > API Tokens). Remember, you’ll only see the token once, so make sure to save it somewhere secure.
- kubectl and Helm installed, as these are necessary for installing components in the cluster and performing k3s upgrades.

---

## Installation

### macOS

#### With Homebrew
```bash
brew install vitobotta/tap/hetzner_k3s
```

#### Binary installation
First, install these dependencies:
- libevent
- bdw-gc
- libyaml
- pcre
- gmp

##### Apple Silicon / ARM
```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v2.4.0/hetzner-k3s-macos-arm64
chmod +x hetzner-k3s-macos-arm64
sudo mv hetzner-k3s-macos-arm64 /usr/local/bin/hetzner-k3s
```

##### Intel / x86
```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v2.4.0/hetzner-k3s-macos-amd64
chmod +x hetzner-k3s-macos-amd64
sudo mv hetzner-k3s-macos-amd64 /usr/local/bin/hetzner-k3s
```

### Linux

NOTE: If you're using certain distributions like Fedora, you might run into a little issue when you try to run hetzner-k3s because of a different version of OpenSSL. The easiest way to fix this, for now, is to run these commands before starting hetzner-k3s:

```bash
export OPENSSL_CONF=/dev/null
export OPENSSL_MODULES=/dev/null
```

For example, you can define a function replacing `hetzner-k3s` in your `.bashrc` or `.zshrc`:

```bash
hetzner-k3s() {
    OPENSSL_CONF=/dev/null OPENSSL_MODULES=/dev/null command hetzner-k3s "$@"
}
```

#### amd64
```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v2.4.0/hetzner-k3s-linux-amd64
chmod +x hetzner-k3s-linux-amd64
sudo mv hetzner-k3s-linux-amd64 /usr/local/bin/hetzner-k3s
```

#### arm
```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v2.4.0/hetzner-k3s-linux-arm64
chmod +x hetzner-k3s-linux-arm64
sudo mv hetzner-k3s-linux-arm64 /usr/local/bin/hetzner-k3s
```

### Windows

For Windows, I recommend using the Linux binary with [WSL](https://learn.microsoft.com/en-us/windows/wsl/install).
