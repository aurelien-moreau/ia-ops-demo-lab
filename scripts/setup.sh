#!/bin/bash
# setup.sh — One-time cluster setup for the demo
# Prerequisites: kubectl configured, ArgoCD installed in 'argocd' namespace
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "🚀 Setting up demo-ia-ops..."
echo ""

# 1. Update repo URL in ArgoCD manifests
if grep -q "YOUR_ORG" "$REPO_ROOT/argocd/root-app.yaml"; then
  echo "⚠  Update the repoURL in argocd/root-app.yaml and argocd/apps/demo-app.yaml"
  echo "   Replace 'YOUR_ORG' with your actual GitHub org/username"
  echo ""
  echo "   Example:"
  echo "   sed -i 's|YOUR_ORG|my-github-user|g' argocd/root-app.yaml argocd/apps/demo-app.yaml"
  exit 1
fi

# 2. Install Python dependencies
echo "📦 Installing Python dependencies..."
cd "$REPO_ROOT/agent"
pip install -r requirements.txt -q
echo "✓ Dependencies installed"

# 3. Check .env
if [ ! -f "$REPO_ROOT/agent/.env" ]; then
  echo ""
  echo "⚠  Create agent/.env from agent/.env.example and set ANTHROPIC_API_KEY"
  echo "   cp agent/.env.example agent/.env"
  exit 1
fi

# 4. Apply ArgoCD root app
echo ""
echo "📡 Applying ArgoCD root application..."
kubectl apply -f "$REPO_ROOT/argocd/root-app.yaml"
echo "✓ Root app applied — ArgoCD will sync demo-app within ~30s"

echo ""
echo "✅ Setup complete!"
echo ""
echo "Monitor the deployment:"
echo "  kubectl get pods -n default -w"
echo "  kubectl get applications -n argocd"
echo ""
echo "Run the demo:"
echo "  ./scripts/demo.sh"
