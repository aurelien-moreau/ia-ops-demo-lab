#!/bin/bash
# teardown.sh — Remove the local lab entirely
set -e

echo "⚠  This will delete the kind cluster and local registry."
read -rp "Are you sure? (yes/no): " confirm
[ "$confirm" = "yes" ] || { echo "Aborted."; exit 0; }

echo ""
echo "Deleting kind cluster demo-ia-ops..."
kind delete cluster --name demo-ia-ops 2>/dev/null && echo "✓ Cluster deleted" || echo "  (cluster not found)"

echo "Removing local registry..."
docker stop kind-registry 2>/dev/null && docker rm kind-registry 2>/dev/null && echo "✓ Registry removed" || echo "  (registry not found)"

echo ""
echo "✓ Lab torn down. Run lab/setup.sh to start fresh."
