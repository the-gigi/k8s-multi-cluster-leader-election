#!/usr/bin/env bash
set -euo pipefail

VERSION=0.9
IMAGE=g1g1/multi-cluster-leader-election

if ! docker buildx ls | grep -q "the-builder"; then
  docker buildx create --name the-builder --driver docker-container
fi
docker buildx use the-builder

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ${IMAGE}:${VERSION} \
  -t ${IMAGE}:latest \
  --label "org.opencontainers.image.created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --label "org.opencontainers.image.revision=$(git rev-parse HEAD)" \
  --label "org.opencontainers.image.source=https://github.com/the-gigi/k8s-multi-cluster-leader-election" \
  --label "org.opencontainers.image.licenses=MIT" \
  --push .

echo "Built and pushed ${IMAGE}:${VERSION} and ${IMAGE}:latest (linux/amd64, linux/arm64)"
