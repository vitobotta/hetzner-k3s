#!/bin/sh
# Tailscale integration tests
# Requires TAILSCALE_AUTH_KEY and TAILSCALE_DOMAIN to be set in the env file
# in addition to HCLOUD_TOKEN, LOCATION, and HK3S.
set -eu
T=./run-single-test.sh

if [ -z "${TAILSCALE_AUTH_KEY:-}" ] || [ -z "${TAILSCALE_DOMAIN:-}" ]; then
  echo "ERROR: TAILSCALE_AUTH_KEY and TAILSCALE_DOMAIN must be set in the env file"
  exit 1
fi

$T config-tailscale-ipv4.yaml
$T config-tailscale-ipv6.yaml
