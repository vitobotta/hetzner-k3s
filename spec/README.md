# Offline regression specs

Run in the development container:

```sh
docker compose -f docker-compose.yml run --rm --no-deps -T hetzner-k3s crystal spec
docker compose -f docker-compose.yml run --rm --no-deps -T hetzner-k3s crystal build --no-codegen src/hetzner-k3s.cr
```

The external-routing specs exercise configuration validation, the real master and
worker script generators, and SSH target selection. Generated shell is executed
with stubbed network commands and an inert installer; filesystem writes go to a
temporary directory. All addresses and credentials are synthetic. No Hetzner API,
SSH connection, cluster creation or k3s installation is performed.

Coverage includes public/private cloud masters, cloud workers, routed generic and
Robot workers, Cilium and Flannel interface selection, multihomed hosts, explicit
cluster IPs, host fallback, invalid configurations and per-node SSH overrides.
