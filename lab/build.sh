#!/bin/bash
# build.sh — Build the demo-app Docker image and load it into the kind cluster.
# Avoids pulling from Docker Hub during the demo (works offline).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="aurelops/ia-ops-demo-app:latest"

echo "📦 Building demo-app..."

cd "$REPO_ROOT/apps/demo-app"

[ -f go.sum ] || go mod tidy

docker build -t "$IMAGE" .

echo "📤 Loading image into kind cluster..."
kind load docker-image "$IMAGE" --name demo-ia-ops

echo ""
echo "✓ Image ready in cluster: $IMAGE"
echo ""
echo "To also push to Docker Hub:"
echo "  docker push $IMAGE"
