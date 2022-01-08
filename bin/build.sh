#!/bin/bash

set -e



IMAGE="vitobotta/hetzner-k3s"

docker build -t ${IMAGE}:v9 \
  --platform=linux/amd64 \
  --cache-from ${IMAGE}:v0.4.8 \
  --build-arg BUILDKIT_INLINE_CACHE=1 .

docker push vitobotta/hetzner-k3s:v0.4.9
