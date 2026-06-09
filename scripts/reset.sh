#!/bin/bash
# reset.sh — Restore healthy DATABASE_URL in ia-ops-argo-app → ArgoCD syncs → pods recover
#
# Requires: ia-ops-argo-app cloned locally.
# Default location: ../ia-ops-argo-app  (override with ARGO_REPO env var)
#
set -euo pipefail

ARGO_REPO="${ARGO_REPO:-$(cd "$(dirname "$0")/../../ia-ops-argo-app" 2>/dev/null && pwd)}"

if [ ! -d "$ARGO_REPO" ]; then
  echo "✗ ia-ops-argo-app not found at: $ARGO_REPO"
  echo "  Clone it first:"
  echo "    git clone git@github.com:aurelien-moreau/ia-ops-argo-app.git ../ia-ops-argo-app"
  echo "  Or set: export ARGO_REPO=/path/to/ia-ops-argo-app"
  exit 1
fi

CONFIG_FILE="$ARGO_REPO/apps/demo-app/k8s/configmap.yaml"

echo "🔄 Restoring healthy DATABASE_URL in $ARGO_REPO..."

cat > "$CONFIG_FILE" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-app-config
  namespace: default
data:
  DATABASE_URL: "postgres://app:s3cr3t@postgres.default.svc.cluster.local:5432/appdb?sslmode=disable"
  APP_ENV: "production"
  LOG_LEVEL: "info"
EOF

git -C "$ARGO_REPO" add apps/demo-app/k8s/configmap.yaml
git -C "$ARGO_REPO" commit -m "fix: restore database configuration"
git -C "$ARGO_REPO" push

echo "✓ Healthy config pushed to github.com/aurelien-moreau/ia-ops-argo-app"

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
