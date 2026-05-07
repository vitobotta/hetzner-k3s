# hetzner-k3s

Crystal CLI tool that provisions production-ready k3s clusters on Hetzner Cloud.

## Build and Run

All build/test commands run inside the Docker dev container, not on the host:

```bash
docker compose run --rm hetzner-k3s <command>
```

Key commands:
- `shards install` — install dependencies
- `crystal build --no-codegen src/hetzner-k3s.cr` — syntax/type check without producing a binary
- `crystal build src/hetzner-k3s.cr` — build debug binary
- `crystal build src/hetzner-k3s.cr --release` — build release binary
- `crystal tool format` — format check
- `crystal build src/hetzner-k3s.cr --release --static` — static build (Linux only)

## Architecture

Entry point: `src/hetzner-k3s.cr` — Admiral-based CLI with subcommands: `create`, `delete`, `upgrade`, `run`

Module layout under `src/`:
- `hetzner/` — Hetzner Cloud API client (firewall, instance, load_balancer, network, ssh_key)
- `configuration/` — YAML config models and validators
- `kubernetes/` — k3s/k8s setup (control_plane, worker, scripts, software, resources)
- `cluster/` — high-level cluster operations (create, delete, upgrade, run)
- `k3s.cr` — k3s release fetching and token management
- `util/` — shell helpers

## Testing

No unit test suite. Only e2e tests in `e2e-tests/` that create/delete real Hetzner clusters (requires API token). These are slow and sequential — not suitable for quick verification.

Use `crystal build --no-codegen` for fast type/syntax checking instead.

## Workflow

- Never commit or push without explicit user permission — always ask first
- Make changes → show what was changed → stop and ask before committing/pushing

## Code Style

- Double quotes for all string literals (`"string"`, not `'string'`)
- 2-space indent, UTF-8, LF line endings (`.editorconfig`)
- Crystal formatter: `crystal tool format`

## Gotchas

- `shard.yml` lists Crystal 1.5.0 but CI builds with 1.14.1 — the `shard.yml` value is stale; use the Docker container's Crystal version as the effective target
- The dev container (Alpine-based) includes kubectl, helm, k9s, stern — useful for debugging running clusters
- Linux release builds are statically linked (`--static`); macOS builds are not
- Dependencies are installed with `shards install --without-development` in CI
