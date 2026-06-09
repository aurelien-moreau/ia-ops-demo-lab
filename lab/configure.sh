#!/bin/bash
# configure.sh — Inject your GitHub repo URL into all ArgoCD manifests.
# Run this ONCE before setup.sh, then commit + push the result.
#
# Usage:
#   ./lab/configure.sh https://github.com/you/demo-ia-ops.git
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLACEHOLDER="https://github.com/YOUR_ORG/demo-ia-ops.git"

REPO_URL="${1:-}"
if [ -z "$REPO_URL" ]; then
  echo "Usage: $0 <github-repo-url>"
  echo "Example: $0 https://github.com/johndoe/demo-ia-ops.git"
  exit 1
fi

echo "Configuring ArgoCD manifests with: $REPO_URL"

# Replace placeholder in every ArgoCD YAML
find "$REPO_ROOT/argocd" -name "*.yaml" | while read -r f; do
  sed -i '' "s|$PLACEHOLDER|$REPO_URL|g" "$f"
  echo "  ✓ $f"
done

# Store the URL for use by other scripts
echo "GITOPS_REPO_URL=$REPO_URL" > "$REPO_ROOT/.lab-env"

echo ""
echo "Done. Now commit and push:"
echo "  git add argocd/ .lab-env"
echo "  git commit -m 'chore: configure ArgoCD repo URL'"
echo "  git push"
echo ""
echo "Then run: ./lab/setup.sh"
