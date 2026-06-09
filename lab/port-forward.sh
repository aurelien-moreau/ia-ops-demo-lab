#!/bin/bash
# port-forward.sh — Start all port-forwards needed for the demo
# Run this in a separate terminal and leave it open.
set -e

echo "Starting port-forwards..."
echo "  K8s Dashboard → http://localhost:8888"
echo "  (ArgoCD and demo-app are on NodePorts — no port-forward needed)"
echo ""
echo "Press Ctrl+C to stop all"
echo ""

# Kill existing port-forwards on this port
lsof -ti:8888 | xargs kill -9 2>/dev/null || true

kubectl port-forward \
  -n kubernetes-dashboard \
  svc/kubernetes-dashboard-kong-proxy 8888:443 \
  2>&1 | grep -v "Handling connection"
