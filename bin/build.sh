#!/bin/bash

set -e

# IMAGE="vitobotta/hetzner-k3s"

# docker build -t ${IMAGE}:v0.5.9 \
#   --platform=linux/amd64 \
#   --cache-from ${IMAGE}:v0.5.8 \
#   --build-arg BUILDKIT_INLINE_CACHE=1 .

# docker push vitobotta/hetzner-k3s:v0.5.9

warble

echo "#!/usr/bin/env java -jar" > dist/hetzner-k3s
cat dist/hetzner-k3s.jar >> dist/hetzner-k3s
chmod +x dist/hetzner-k3s
