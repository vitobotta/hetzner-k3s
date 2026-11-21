# hetzner-k3s

Crystal CLI tool that provisions production-ready k3s clusters on Hetzner Cloud.

## Build and Run

All build/test commands run inside the Docker dev container, not on the host:

```bash
docker compose run --rm --no-deps -T hetzner-k3s <command>
```

`--no-deps` skips side services and `-T` disables TTY allocation, which is what
makes the command usable from scripts. `docker-compose.override.yml` is
gitignored and holds host-specific mounts, so a fresh clone uses
`docker-compose.yml` alone. `lib/` and `bin/` are gitignored too: a new worktree
needs `shards install` before it can compile or run specs.

Key commands:
- `shards install`: install dependencies
- `crystal build --no-codegen src/hetzner-k3s.cr`: type/syntax check without producing a binary (fastest gate)
- `crystal build src/hetzner-k3s.cr`: build debug binary
- `crystal build src/hetzner-k3s.cr --release`: build release binary
- `crystal build src/hetzner-k3s.cr --release --static`: static Linux build, the form CI ships
- `crystal spec`: offline spec suite (46 examples, about 0.1 s)
- `crystal tool format --check <files>`: formatting check on the files you touched only
- `mkdocs build --strict`: build the docs site

## Architecture

Entry point: `src/hetzner-k3s.cr`, an Admiral-based CLI with subcommands `create`,
`delete`, `upgrade`, `releases` and `run`. `CLI::VERSION` and
`CLI::CONFIG_FORMAT_VERSION` are defined in the same file.

151 Crystal files, about 9,200 lines, under `src/`:
- `hetzner/`: Hetzner Cloud API client, one subdirectory per resource (`firewall`, `instance`, `load_balancer`, `network`, `placement_group`, `ssh_key`) with `create`, `delete` and `find`, plus the list endpoints and `robot/` for dedicated servers
- `configuration/`: YAML config models in `models/` and one validator per field or combination in `validators/`. `loader.cr` rejects any `config_format_version` other than `CLI::CONFIG_FORMAT_VERSION` (`loader.cr:131`), so a breaking config shape change needs a version bump plus a note in `docs/Important_upgrade_notes.md`
- `cluster/`: high-level operations (`create`, `delete`, `upgrade`, `run`) and the per-resource managers (firewall, network, load balancer, placement group), plus `instance_builder`, `node_detection` and `external_node_validator`
- `kubernetes/`: `control_plane/setup`, `worker/setup`, `worker/external_setup`, `local_firewall/setup`, the script generators in `script/` (`master_generator`, `worker_generator`, `labels_and_taints_generator`), the addon installers in `software/` (including the pinned CCM, CSI, SUC and cluster-autoscaler versions), typed pod and deployment manifests in `resources/`, and `kubeconfig_manager`
- `k3s.cr`: k3s release fetching and token management
- `util/`: shell, SSH and prefixed IO helpers

`templates/` holds the shell and manifests the generators render:
`master_install_script.sh`, `worker_install_script.sh`, `cloud_init.yaml`,
`cloud_init_wait_script.sh`, `cilium_values.yaml`, `firewall/`, `ssh/`, the two
upgrade plan manifests and the Hetzner cloud secret manifest. They are embedded
with `read_file` at compile time, so editing one requires a rebuild.

## Testing

The offline suite in `spec/` is the real gate:

```bash
docker compose run --rm --no-deps -T hetzner-k3s crystal spec
```

`spec/routing_spec_helper.cr` runs the generated shell with stubbed `curl`, `ip`,
`ssh`, `systemctl` and `journalctl`, and writes to a temporary directory. No API
token, no network, no cluster: two spec files, 46 examples, about 0.1 s.

`e2e-tests/` creates and deletes real Hetzner clusters, and `run-all-tests.sh`
loops a distro and SSH-port matrix against them. It needs a real token, takes a
long time, and is never the right way to verify a change.

CI does not run the specs. `.github/workflows/ci.yaml` only builds four binaries
(macOS amd64 and arm64, Linux amd64 and arm64), so a green check says nothing
about tests: run `crystal spec` yourself and report the example count.

## Docs

User documentation lives in `docs/*.md` and is published to
https://vitobotta.github.io/hetzner-k3s/ by `.github/workflows/publish-docs.yml`
on any push to `main` that touches `docs/**` or `mkdocs.yml`, via
`mkdocs gh-deploy`. `mkdocs build --strict` works in the container and catches
bad nav entries and links in about 0.3 s.

`README.md` duplicates parts of `docs/` (install URLs, the sample monthly costs
table), so a user-facing change usually has to land in both.

## Release

Pushing a `v*` tag runs `.github/workflows/release.yml`, which calls `ci.yaml`,
verifies the four binaries exist, uploads them, and creates the GitHub release
itself with a `WIP` body. Never create a release by hand.

The version lives in three places and all of them must move together:
- `VERSION` in `src/hetzner-k3s.cr`
- download URLs in `README.md`
- download URLs in `docs/Installation.md` (four of them)

`grep -rn '<old version>' --include='*.cr' --include='*.md' .` must return
nothing before tagging. Linux binaries are statically linked, macOS ones are
not, and the Linux arm64 job runs under QEMU and takes about 20 minutes.

## Workflow

- Never commit or push without explicit user permission: always ask first
- Make changes, show what changed, stop and ask before committing or pushing

## Code Style

- Double quotes for all string literals (`"string"`, not `'string'`)
- 2-space indent, UTF-8, LF line endings (`.editorconfig`)
- `crystal tool format --check` on the files you touched. Do not run bare `crystal tool format`: it rewrites files in place, and under the container's formatter it would reformat a dozen untouched files.

## Gotchas

- Three Crystal versions, and the container is the floor: the dev container has 1.14.0 (Alpine package), `shard.yml` requires `>= 1.20.0`, and CI pins 1.20.2. Code has to compile on 1.14.0, so treat any 1.15 or newer language and stdlib feature as unavailable until the container image moves.
- Formatter output differs between those versions: `crystal tool format --check` fails on untouched files, `src/hetzner-k3s.cr` included. Only report or fix formatting on files in the diff, and check the base revision before calling a formatting change a regression.
- The container's Shards 0.18 does not enforce the `crystal:` requirement in `shard.yml`, so `shards install` succeeds despite the version mismatch.
- `create` re-runs the master install script on every master unconditionally, and redeploys the worker install script on existing cloud workers. A change to `templates/master_install_script.sh` or `templates/worker_install_script.sh` therefore reaches real nodes on the next `create`, including clusters that are already running.
- External (Robot) nodes are skipped only when `/etc/initialized` is `true` and `k3s-agent` is active (`worker/external_setup.cr#node_initialized?`).
- The dev container (Alpine-based) includes kubectl, helm, k9s, stern and krew plugins, plus mkdocs-material, Go, Node and Python. `docker compose up -d` with `docker compose exec` is for interactive work; the `run --rm` form is for one-shot commands.
- CI installs dependencies with `shards install --without-development`.
