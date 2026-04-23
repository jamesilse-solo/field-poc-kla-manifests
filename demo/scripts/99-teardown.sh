#!/usr/bin/env bash
# 99-teardown.sh — remove all demo additions from the cluster
# Does NOT remove the base AGW setup — only demo/ additions

set -euo pipefail
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFESTS="${DEMO_DIR}/manifests"

echo ""
echo "Removing KLA demo additions..."
echo ""

# Remove demo manifests
kubectl delete -f "${MANIFESTS}/soloio-docs-mcp.yaml" --ignore-not-found
kubectl delete -f "${MANIFESTS}/openai-backend.yaml" --ignore-not-found
kubectl delete -f "${MANIFESTS}/dex.yaml" --ignore-not-found
kubectl delete secret openai-secret -n agentgateway-system --ignore-not-found

# Restore base auth policy (re-apply from base)
kubectl apply -f "${DEMO_DIR}/../manifests/base/auth-policy.yaml" 2>/dev/null && \
  echo "  Restored base auth policy (Keycloak)" || \
  echo "  Base auth policy restore skipped (ArgoCD will reconcile)"

# Remove AgentRegistry
helm uninstall agentregistry -n agentregistry 2>/dev/null && echo "  AgentRegistry uninstalled" || true
kubectl delete namespace agentregistry --ignore-not-found

# Re-enable ArgoCD sync
kubectl patch application agw-management -n argocd \
  --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":false,"selfHeal":true}}}}' \
  2>/dev/null && echo "  ArgoCD sync re-enabled" || true

# Kill background port-forwards
pkill -f "kubectl port-forward.*agentregistry" 2>/dev/null || true
pkill -f "kubectl port-forward.*dex" 2>/dev/null || true

echo ""
echo "Teardown complete. Base AGW setup intact."
echo "Run 'argocd app sync agw-management' to fully reconcile if needed."
