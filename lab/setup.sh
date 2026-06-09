#!/bin/bash
# setup.sh — Full local lab: kind cluster + ArgoCD + Reloader + K8s Dashboard
#
# Prerequisites (macOS):
#   brew install kind kubectl helm
#   Docker Desktop running
#
set -euo pipefail

LAB_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$LAB_DIR/.." && pwd)"

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; R='\033[0;31m'; N='\033[0m'
ok()      { echo -e "${G}✓${N}  $*"; }
info()    { echo -e "${C}→${N}  $*"; }
warn()    { echo -e "${Y}⚠${N}  $*"; }
die()     { echo -e "${R}✗${N}  $*" >&2; exit 1; }
section() { echo ""; echo -e "${C}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"; echo ""; }

# ─── Prerequisites ────────────────────────────────────────────────────────────
section "Checking prerequisites"
for cmd in docker kind kubectl helm; do
  command -v "$cmd" &>/dev/null || die "$cmd not found — install it first"
  ok "$cmd"
done
docker info &>/dev/null || die "Docker is not running"

# ─── Kind cluster ─────────────────────────────────────────────────────────────
section "Kind cluster (demo-ia-ops)"
if kind get clusters 2>/dev/null | grep -q "^demo-ia-ops$"; then
  warn "Cluster already exists — skipping creation"
else
  info "Creating cluster..."
  kind create cluster --config "$LAB_DIR/kind.yaml"
  ok "Cluster created"
fi
kubectl cluster-info --context kind-demo-ia-ops

# ─── Build & push demo-app image ──────────────────────────────────────────────
section "Building demo-app image"
bash "$LAB_DIR/build.sh"

# ─── ArgoCD ───────────────────────────────────────────────────────────────────
section "Installing ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
  info "Applying ArgoCD manifests..."
  kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
fi

info "Waiting for ArgoCD server (~90s on first install)..."
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=180s
ok "ArgoCD ready"

# Expose via NodePort on host:8080
kubectl patch svc argocd-server -n argocd -p \
  '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8080,"nodePort":30080,"name":"https"}]}}'

# Speed up sync polling to 30s (default is 3 minutes)
kubectl patch configmap argocd-cm -n argocd --type=merge \
  -p '{"data":{"timeout.reconciliation":"30s"}}'
ok "Sync interval set to 30s"

ARGO_PASS=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d)

# ─── Stakater Reloader ────────────────────────────────────────────────────────
# Reloader watches ConfigMaps and automatically rolls Deployments when they change.
# Without this, updating a ConfigMap used via envFrom does NOT restart pods.
section "Installing Stakater Reloader"
if ! kubectl get deployment reloader-reloader -n default &>/dev/null; then
  kubectl apply -f \
    https://raw.githubusercontent.com/stakater/Reloader/master/deployments/kubernetes/reloader.yaml
  kubectl wait --for=condition=available deployment/reloader-reloader \
    --timeout=60s 2>/dev/null || true
fi
ok "Reloader installed"

# ─── Kubernetes Dashboard ─────────────────────────────────────────────────────
section "Installing Kubernetes Dashboard"
if ! kubectl get deployment -n kubernetes-dashboard -l "app.kubernetes.io/name=kubernetes-dashboard" \
     --no-headers 2>/dev/null | grep -q .; then
  helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ 2>/dev/null || true
  helm repo update -q
  helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
    --create-namespace --namespace kubernetes-dashboard \
    --set app.ingress.enabled=false \
    --wait --timeout=120s
fi
ok "Dashboard installed"

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: demo-admin
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: demo-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: demo-admin
    namespace: kubernetes-dashboard
---
apiVersion: v1
kind: Secret
metadata:
  name: demo-admin-token
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: demo-admin
type: kubernetes.io/service-account-token
EOF
sleep 3
DASHBOARD_TOKEN=$(kubectl get secret demo-admin-token \
  -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d)

# ─── Bootstrap ArgoCD Apps via root Application ───────────────────────────────
section "Bootstrapping via ArgoCD root Application"

info "Applying root-app (App of Apps)..."
kubectl apply -f "$REPO_ROOT/argocd/root-app.yaml"
ok "root-app applied"

info "Waiting for ArgoCD to create child Applications (~30s)..."
for app in postgres demo-app; do
  for i in $(seq 1 12); do
    kubectl get application "$app" -n argocd &>/dev/null && break
    sleep 5
  done
  ok "Application '$app' created by ArgoCD"
done

info "Waiting for postgres Deployment to become available..."
kubectl wait --for=condition=available deployment/postgres \
  -n default --timeout=120s
ok "PostgreSQL ready"

info "Waiting for demo-app Deployment to become available..."
kubectl wait --for=condition=available deployment/demo-app \
  -n default --timeout=120s
ok "demo-app ready"

# ─── Summary ──────────────────────────────────────────────────────────────────
section "Lab ready"
echo -e "  ${G}demo-app      ${N}→ ${C}http://localhost:8081${N}"
echo -e "  ${G}ArgoCD UI     ${N}→ ${C}https://localhost:8080${N}"
echo -e "               username: ${C}admin${N}  password: ${C}${ARGO_PASS}${N}"
echo -e "  ${G}K8s Dashboard ${N}→ ${C}./lab/port-forward.sh${N} then http://localhost:8888"
echo ""
echo -e "  Dashboard token saved to: ${C}./lab/dashboard-token.txt${N}"
echo "$DASHBOARD_TOKEN" > "$LAB_DIR/dashboard-token.txt"
echo ""
echo "Demo flow:"
echo "  1. Open http://localhost:8081         → HEALTHY (green)"
echo "  2. ./scripts/break.sh                → ArgoCD syncs broken config"
echo "  3. Refresh browser                   → DEGRADED (red) within 30s"
echo "  4. cd agent && python main.py        → AI investigates + fixes via Git"
echo "  5. Refresh browser                   → HEALTHY (green)"
