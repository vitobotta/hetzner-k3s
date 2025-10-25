#!/bin/sh
set -eux

shards install --without-development

if [ "${CRYSTAL_BUILD_STATIC:-false}" = "true" ]; then
  crystal build src/hetzner-k3s.cr --release --static
else
  crystal build src/hetzner-k3s.cr --release
fi

chmod +x hetzner-k3s
cp hetzner-k3s "${FILENAME}"
