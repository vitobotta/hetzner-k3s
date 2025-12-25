# Contributing and Support

hetzner-k3s is an open source project, and contributions are welcome!

---

## Getting Help

### GitHub Issues

If you're running into issues with the tool, please [open an issue](https://github.com/vitobotta/hetzner-k3s/issues). Include:

- Your configuration file (with sensitive values redacted)
- Full output with debug mode enabled (`DEBUG=true hetzner-k3s ...`)
- Your operating system and hetzner-k3s version
- Steps to reproduce the issue

### GitHub Discussions

For general questions, ideas, or discussions, use [GitHub Discussions](https://github.com/vitobotta/hetzner-k3s/discussions). This is a good place for:

- Questions about best practices
- Feature suggestions
- Sharing how you're using hetzner-k3s

### Documentation

Check the [Troubleshooting](Troubleshooting.md) page for solutions to common issues.

---

## Contributing Code

Pull requests are welcome! Whether it's fixing a bug, improving documentation, or adding a feature.

### Development Environment

hetzner-k3s is built using [Crystal](https://crystal-lang.org/). You can develop using:

- **VS Code with Dev Containers** (recommended)
- **Docker Compose**
- **Local Crystal installation**

### VS Code Setup

1. Install [Visual Studio Code](https://code.visualstudio.com/) and the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. Open the project in VS Code (`code .` in the repository root)
3. Click "Reopen in Container" when prompted
4. Wait for the container to build
5. Open a terminal inside the container

**Note:** If you can't find the Dev Containers extension, ensure you're using the official VS Code build (some extensions are disabled in Open Source builds).

### Docker Compose Setup

If you prefer not to use VS Code:

```bash
# Build and start the development container
docker compose up -d

# Access the container
docker compose exec hetzner-k3s bash
```

### Running the Tool

Inside the development container:

```bash
# Run without building
crystal run ./src/hetzner-k3s.cr -- create --config cluster_config.yaml

# Build a binary
crystal build ./src/hetzner-k3s.cr --static
```

The `--static` flag creates a statically linked binary that doesn't depend on external libraries.

---

## Supporting the Project

If you or your company find this project useful, please consider [becoming a sponsor](https://github.com/sponsors/vitobotta). Your support helps:

- Fund ongoing development and maintenance
- Enable new features
- Keep the project actively maintained

### Current Sponsors

**Platinum:** [Alamos GmbH](https://alamos.gmbh)

**Backers:** [@deubert-it](https://github.com/deubert-it), [@jonasbadstuebner](https://github.com/jonasbadstuebner), [@ricristian](https://github.com/ricristian), [@QuentinFAIDIDE](https://github.com/QuentinFAIDIDE)

---

## Consulting

Need help with hetzner-k3s, Kubernetes on Hetzner, or related infrastructure? The maintainer is available for consulting engagements.

Contact: [vitobotta.com](https://vitobotta.com/)
