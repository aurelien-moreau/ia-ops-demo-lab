#!/bin/bash
# demo.sh — Full conference demo orchestration script
# Run this end-to-end for the presentation

set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

banner() {
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}  $1${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
}

pause() {
  echo -e "${YELLOW}[Press Enter to continue...]${RESET}"
  read -r
}

# ─── Step 1: Show healthy state ───────────────────────────────────────────────
banner "STEP 1 — Healthy Production Stack"
echo "ArgoCD managing our demo-app via GitOps:"
echo ""
kubectl get pods -n default
echo ""
kubectl get application demo-app -n argocd 2>/dev/null || echo "(ArgoCD app not yet installed — run scripts/setup.sh first)"
pause

# ─── Step 2: Inject the failure ───────────────────────────────────────────────
banner "STEP 2 — Injecting Configuration Failure"
echo -e "${RED}Simulating a bad deployment: DATABASE_URL misconfigured${RESET}"
echo ""
"$REPO_ROOT/scripts/break.sh"
echo ""
echo "Waiting for ArgoCD to sync and pods to crash..."
sleep 10

# Wait for CrashLoopBackOff
for i in $(seq 1 12); do
  status=$(kubectl get pods -n default -l app=demo-app --no-headers 2>/dev/null | awk '{print $3}' | head -1)
  echo "  Pods status: $status (${i}0s elapsed)"
  if echo "$status" | grep -qE "CrashLoopBackOff|Error|OOMKilled"; then
    break
  fi
  sleep 10
done

echo ""
echo -e "${RED}🚨 INCIDENT: Pods are crashing!${RESET}"
kubectl get pods -n default
pause

# ─── Step 3: Launch the AI agent ──────────────────────────────────────────────
banner "STEP 3 — AI Ops Agent Takes Over"
echo -e "${CYAN}The AI agent is now investigating and resolving the incident autonomously...${RESET}"
echo ""

source "$REPO_ROOT/agent/.env" 2>/dev/null || true
export REPO_PATH="$REPO_ROOT"

cd "$REPO_ROOT/agent" && python main.py

# ─── Done ─────────────────────────────────────────────────────────────────────
banner "DEMO COMPLETE"
echo "The full GitOps loop:"
echo "  1. Incident detected"
echo "  2. AI investigated logs & configuration"
echo "  3. Root cause identified: invalid DATABASE_URL"
echo "  4. Fix committed to Git"
echo "  5. ArgoCD synced automatically"
echo "  6. Application healthy"
echo ""
echo -e "${GREEN}No humans were paged at 3am. ✓${RESET}"
echo ""
