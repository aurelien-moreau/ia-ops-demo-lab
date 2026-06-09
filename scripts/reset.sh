#!/bin/bash
# reset.sh — Restore a healthy DATABASE_URL in Git → ArgoCD syncs → pods recover
# Use this to reset the demo between runs.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/apps/demo-app/k8s/configmap.yaml"

echo "🔄 Restoring healthy DATABASE_URL into Git..."

cat > "$CONFIG_FILE" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-app-config
  namespace: default
data:
  DATABASE_URL: "postgres://app:s3cr3t@postgres.default.svc.cluster.local:5432/appdb"
  APP_ENV: "production"
  LOG_LEVEL: "info"
EOF

git -C "$REPO_ROOT" add apps/demo-app/k8s/configmap.yaml
git -C "$REPO_ROOT" commit -m "fix: restore database configuration"
git -C "$REPO_ROOT" push

echo "✓ Healthy config pushed to GitHub"

echo ""
echo "Triggering ArgoCD sync..."
if command -v argocd &>/dev/null; then
  argocd app sync demo-app --force 2>/dev/null && echo "✓ argocd sync triggered"
else
  kubectl annotate application demo-app -n argocd \
    argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null && echo "✓ ArgoCD refresh triggered"
fi

echo ""
echo "  open http://localhost:8081   ← turns GREEN within ~30s"
