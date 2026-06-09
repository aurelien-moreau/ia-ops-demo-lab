#!/bin/bash
# install-dashboard.sh — Kubernetes Dashboard (optionnel, pas nécessaire pour la démo)
# Installe via manifests YAML directs — plus stable que le chart Helm.
set -euo pipefail

LAB_DIR="$(cd "$(dirname "$0")" && pwd)"

G='\033[0;32m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "${G}✓${N}  $*"; }
info() { echo -e "${C}→${N}  $*"; }

info "Deploying Kubernetes Dashboard v2.7.0..."
kubectl apply -f \
  https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

info "Waiting for dashboard to be ready..."
kubectl wait --for=condition=available deployment/kubernetes-dashboard \
  -n kubernetes-dashboard --timeout=120s
ok "Dashboard ready"

info "Creating admin ServiceAccount..."
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
TOKEN=$(kubectl get secret demo-admin-token \
  -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d)

echo "$TOKEN" > "$LAB_DIR/dashboard-token.txt"
ok "Token saved to lab/dashboard-token.txt"

echo ""
echo "Pour accéder au Dashboard :"
echo "  ./lab/port-forward.sh"
echo "  open http://localhost:8888"
echo "  Coller le token depuis lab/dashboard-token.txt"
