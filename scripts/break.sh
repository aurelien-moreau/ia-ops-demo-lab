#!/bin/bash
# break.sh — Inject a malformed DATABASE_URL into Git → ArgoCD syncs → pods crash
#
# This simulates a bad deployment reaching production via GitOps.
# Stakater Reloader will restart the pods as soon as ArgoCD applies the ConfigMap.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/apps/demo-app/k8s/configmap.yaml"

echo "⚡ Injecting broken DATABASE_URL into Git..."

cat > "$CONFIG_FILE" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-app-config
  namespace: default
data:
  DATABASE_URL: "postgres://"
  APP_ENV: "production"
  LOG_LEVEL: "info"
EOF

git -C "$REPO_ROOT" add apps/demo-app/k8s/configmap.yaml
git -C "$REPO_ROOT" commit -m "fix: update database endpoint configuration"
git -C "$REPO_ROOT" push

echo "✓ Broken config pushed to GitHub"

# Force ArgoCD to sync immediately (don't wait for 30s polling)
echo ""
echo "Triggering ArgoCD sync..."
if command -v argocd &>/dev/null; then
  argocd app sync demo-app --force 2>/dev/null && echo "✓ argocd sync triggered"
else
  kubectl annotate application demo-app -n argocd \
    argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null && echo "✓ ArgoCD refresh triggered"
fi

echo ""
echo "What to expect:"
echo "  ~10s  ArgoCD applies the ConfigMap"
echo "  ~10s  Reloader detects the change → rolling restart"
echo "  ~20s  New pods start → DB check fails → /health returns 503"
echo "  ~40s  Liveness probe fails → CrashLoopBackOff"
echo ""
echo "Watch it live:"
echo "  kubectl get pods -n default -w"
echo "  open http://localhost:8081   ← turns RED"
