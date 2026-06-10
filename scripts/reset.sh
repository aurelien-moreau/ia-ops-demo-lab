#!/bin/bash
# reset.sh — Restore the demo environment to its initial healthy state.
# Resets: demo-app replicas → 2, postgres max_connections → 30, DATABASE_URL healthy.
set -euo pipefail

ARGO_REPO="${ARGO_REPO:-$(cd "$(dirname "$0")/../../ia-ops-argo-app" 2>/dev/null && pwd)}"

if [ ! -d "$ARGO_REPO" ]; then
  echo "✗ ia-ops-argo-app not found at: $ARGO_REPO"
  echo "  Clone it: git clone git@github.com:aurelien-moreau/ia-ops-argo-app.git ../ia-ops-argo-app"
  exit 1
fi

echo "🔄 Resetting demo environment..."

# 1. Restore demo-app configmap (healthy DATABASE_URL)
cat > "$ARGO_REPO/apps/demo-app/k8s/configmap.yaml" << 'EOF'
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

# 2. Restore demo-app to 2 replicas
sed -i '' 's/^\(  replicas: \)[0-9]*/\12/' "$ARGO_REPO/apps/demo-app/k8s/deployment.yaml"

# 3. Restore postgres max_connections to 30
sed -i '' 's/max_connections=[0-9]*/max_connections=30/' "$ARGO_REPO/apps/postgres/k8s/deployment.yaml"

git -C "$ARGO_REPO" add apps/
git -C "$ARGO_REPO" commit -m "fix: reset demo environment to initial state" 2>/dev/null || echo "  (nothing to commit)"
git -C "$ARGO_REPO" push

echo "✓ Reset pushed to ia-ops-argo-app"

echo ""
echo "Triggering ArgoCD sync..."
if command -v argocd &>/dev/null; then
  argocd app sync demo-app --force 2>/dev/null || true
  argocd app sync postgres --force 2>/dev/null || true
else
  kubectl annotate application demo-app postgres -n argocd \
    argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null || true
fi

echo ""
echo "  open http://localhost:8081   ← turns GREEN within ~30s"
