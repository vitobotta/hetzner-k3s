# Installation

Get hetzner-k3s running on your system in under a minute.

---

## Prerequisites

Before installing hetzner-k3s, you'll need:

| Requirement | Description |
|-------------|-------------|
| **Hetzner Cloud account** | [Sign up here](https://hetzner.cloud/?ref=mqx6KKKwyook) if you don't have one |
| **API token** | Create one in Cloud Console → Security → API Tokens (read & write permissions) |
| **SSH key pair** | For accessing cluster nodes |
| **kubectl** | For interacting with your cluster ([installation guide](https://kubernetes.io/docs/tasks/tools/#kubectl)) |
| **Helm** | For installing applications ([installation guide](https://helm.sh/docs/intro/install/)) |

---

## macOS

### Homebrew (Recommended)

```bash
brew install vitobotta/tap/hetzner_k3s
```

Homebrew also works on Linux — see the [Linux section](#linux) below.

### Binary Installation

If you prefer not to use Homebrew, install the required dependencies first:

- libevent
- bdw-gc
- libyaml
- pcre
- gmp

**Apple Silicon:**
```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v2.4.3/hetzner-k3s-macos-arm64
chmod +x hetzner-k3s-macos-arm64
sudo mv hetzner-k3s-macos-arm64 /usr/local/bin/hetzner-k3s
```

**Intel:**
```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v2.4.3/hetzner-k3s-macos-amd64
chmod +x hetzner-k3s-macos-amd64
sudo mv hetzner-k3s-macos-amd64 /usr/local/bin/hetzner-k3s
```

---

## Linux

### Homebrew (Recommended)

```bash
brew install vitobotta/tap/hetzner_k3s
```

### amd64 (x86_64)

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v2.4.3/hetzner-k3s-linux-amd64
chmod +x hetzner-k3s-linux-amd64
sudo mv hetzner-k3s-linux-amd64 /usr/local/bin/hetzner-k3s
```

### arm64 (ARM)

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v2.4.3/hetzner-k3s-linux-arm64
chmod +x hetzner-k3s-linux-arm64
sudo mv hetzner-k3s-linux-arm64 /usr/local/bin/hetzner-k3s
```

### Fedora and Similar Distributions

Some distributions (like Fedora) may have OpenSSL compatibility issues. If you encounter errors, set these environment variables before running hetzner-k3s:

```bash
export OPENSSL_CONF=/dev/null
export OPENSSL_MODULES=/dev/null
```

For convenience, add a wrapper function to your `~/.bashrc` or `~/.zshrc`:

```bash
hetzner-k3s() {
    OPENSSL_CONF=/dev/null OPENSSL_MODULES=/dev/null command hetzner-k3s "$@"
}
```

---

## Windows

Use the Linux binary with [WSL (Windows Subsystem for Linux)](https://learn.microsoft.com/en-us/windows/wsl/install).

After installing WSL, follow the Linux installation instructions above.

---

## Verify Installation

Check that hetzner-k3s is installed correctly:

```bash
hetzner-k3s --version
```

You should see the version number displayed.

---

## Next Steps

Now that hetzner-k3s is installed:

1. **[Create your first cluster](Creating_a_cluster.md)** — Configuration reference and detailed options
2. **[Set up a complete stack](Setting_up_a_cluster.md)** — Tutorial with ingress, TLS, and a sample application

---

## Updating

To update to the latest version:

**Homebrew:**
```bash
brew upgrade vitobotta/tap/hetzner_k3s
```

**Binary installations:** Download and replace the binary using the same steps as the initial installation.

Check the [releases page](https://github.com/vitobotta/hetzner-k3s/releases) for the latest version and changelog.
