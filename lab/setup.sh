#!/bin/bash
# setup.sh — Full local lab: kind cluster + ArgoCD + Reloader + K8s Dashboard
#
# Prerequisites (macOS):
#   brew install kind kubectl helm
#   Docker Desktop running
#
# The demo-app image (aurelops/ia-ops-demo-app:latest) is pulled from Docker Hub
# automatically when ArgoCD deploys the app — no local build needed.
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

# ─── ArgoCD ───────────────────────────────────────────────────────────────────
section "Installing ArgoCD"

_install_argocd() {
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  info "Applying ArgoCD manifests (server-side to avoid CRD annotation size limit)..."
  kubectl apply -n argocd --server-side \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  info "Waiting for ArgoCD server (~90s)..."
  kubectl wait --for=condition=available deployment/argocd-server \
    -n argocd --timeout=180s
  ok "ArgoCD ready"
  kubectl patch svc argocd-server -n argocd -p \
    '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8080,"nodePort":30080,"name":"https"}]}}'
  kubectl patch configmap argocd-cm -n argocd --type=merge \
    -p '{"data":{"timeout.reconciliation":"30s"}}'
  ok "Sync interval set to 30s"
}

# If deployment exists but initial-admin-secret is missing → incomplete install → reinstall
if kubectl get deployment argocd-server -n argocd &>/dev/null && \
   ! kubectl get secret argocd-initial-admin-secret -n argocd &>/dev/null; then
  warn "ArgoCD install incomplete (initial-admin-secret missing) — reinstalling..."
  kubectl delete namespace argocd --wait=true
  _install_argocd
elif ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
  _install_argocd
else
  ok "ArgoCD already installed"
  kubectl patch svc argocd-server -n argocd -p \
    '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8080,"nodePort":30080,"name":"https"}]}}' \
    2>/dev/null || true
  kubectl patch configmap argocd-cm -n argocd --type=merge \
    -p '{"data":{"timeout.reconciliation":"30s"}}' 2>/dev/null || true
fi

ARGO_PASS=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")

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

# ─── Kubernetes Dashboard (optionnel) ────────────────────────────────────────
# Non installé automatiquement — voir lab/install-dashboard.sh si besoin.
# Pour la démo, l'UI ArgoCD (https://localhost:8080) est suffisante.

# ─── Bootstrap ArgoCD Apps ────────────────────────────────────────────────────
section "Bootstrapping via ArgoCD root Application"

GITOPS_RAW="https://raw.githubusercontent.com/aurelien-moreau/ia-ops-argo-app/main"

info "Applying root-app (App of Apps)..."
kubectl apply -f "$GITOPS_RAW/argocd/root-app.yaml"
ok "root-app appliqué — ArgoCD va créer les Applications demo-app et postgres"

info "Waiting for child Applications to appear (ArgoCD sync, max 90s)..."
for app in postgres demo-app; do
  found=0
  for i in $(seq 1 18); do
    if kubectl get application "$app" -n argocd &>/dev/null; then
      found=1; break
    fi
    echo -e "  ${C}[${i}/18]${N} attente de l'Application '$app'..."
    sleep 5
  done
  [ "$found" -eq 1 ] && ok "Application '$app' créée" \
    || die "Application '$app' non créée après 90s — vérifier ArgoCD UI https://localhost:8080"
done

info "Waiting for postgres to be ready..."
kubectl wait --for=condition=available deployment/postgres \
  -n default --timeout=120s
ok "PostgreSQL ready"

info "Waiting for demo-app to be ready (pulling aurelops/ia-ops-demo-app from Docker Hub)..."
kubectl wait --for=condition=available deployment/demo-app \
  -n default --timeout=180s
ok "demo-app ready"

# ─── Summary ──────────────────────────────────────────────────────────────────
section "Lab ready"

echo -e "  ${G}demo-app   ${N}→ ${C}http://localhost:8081${N}"
echo -e "  ${G}ArgoCD UI  ${N}→ ${C}https://localhost:8080${N}  (accepter le cert auto-signé)"
echo ""
echo -e "  ┌─────────────────────────────────────┐"
echo -e "  │  ArgoCD credentials                 │"
echo -e "  │  username : ${C}admin${N}                   │"
if [ -n "$ARGO_PASS" ]; then
echo -e "  │  password : ${C}${ARGO_PASS}${N}"
echo -e "  └─────────────────────────────────────┘"
else
echo -e "  │  password : ${R}non trouvé${N} — lancer :    │"
echo -e "  │  ${C}kubectl get secret argocd-initial-admin-secret${N} │"
echo -e "  │  ${C}  -n argocd -o jsonpath='{.data.password}'${N} │"
echo -e "  │  ${C}  | base64 -d${N}                      │"
echo -e "  └─────────────────────────────────────┘"
fi
echo ""
echo -e "  ${Y}K8s Dashboard${N} → optionnel : ${C}./lab/install-dashboard.sh${N}"
echo ""
echo -e "${C}━━━ Demo flow ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""
echo "  1. open http://localhost:8081              → HEALTHY (vert)"
echo "  2. ./scripts/break.sh                     → ArgoCD sync config cassée"
echo "  3. Rafraîchir le browser                  → DEGRADED (rouge) en ~30s"
echo "  4. cd agent && source .env && python main.py"
echo "  5. Rafraîchir le browser                  → HEALTHY (vert)"
echo ""
