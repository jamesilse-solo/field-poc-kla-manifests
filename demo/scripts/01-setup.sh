#!/usr/bin/env bash
# 01-setup.sh — deploy all demo additions to the KLA cluster
# Prerequisite: source demo/.env (run 00-preflight.sh first)
# Does NOT replace existing base setup — adds Dex, OpenAI, docs MCP, AgentRegistry on top.

set -euo pipefail
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFESTS="${DEMO_DIR}/manifests"

log() { echo ""; echo "── $*"; }

# ── Load env
if [[ -f "${DEMO_DIR}/.env" ]]; then
  source "${DEMO_DIR}/.env"
fi
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"

log "Deploying Dex identity provider"
kubectl apply -f "${MANIFESTS}/dex.yaml"
kubectl rollout status deployment/dex -n dex --timeout=120s
echo "  Dex running: http://dex.dex.svc.cluster.local:5556 (in-cluster)"

log "Applying demo auth policy (Dex inline JWKS, replaces Keycloak)"
# Remove syncPolicy entirely from both ArgoCD apps (selfHeal: true would revert manual applies)
kubectl patch application agw-config -n argocd \
  --type json -p '[{"op":"remove","path":"/spec/syncPolicy"}]' 2>/dev/null && \
  echo "  ArgoCD auto-sync removed for agw-config" || \
  echo "  agw-config syncPolicy already absent"
kubectl patch application agw-management -n argocd \
  --type json -p '[{"op":"remove","path":"/spec/syncPolicy"}]' 2>/dev/null && \
  echo "  ArgoCD auto-sync removed for agw-management" || \
  echo "  agw-management syncPolicy already absent"
kubectl apply -f "${MANIFESTS}/auth-policy-dex.yaml"
echo "  Auth policy updated — issuer: dex.dex.svc.cluster.local:5556"

log "Adding search.solo.io MCP backend"
kubectl apply -f "${MANIFESTS}/soloio-docs-mcp.yaml"
echo "  Solo.io docs MCP: ${GATEWAY_URL}/mcp/docs"

log "Deploying OpenAI backend"
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  kubectl create secret generic openai-secret -n agentgateway-system \
    --from-literal=api-key="${OPENAI_API_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -
  # Apply backend manifest (secret is already in cluster; skip the Secret stanza)
  grep -v "PLACEHOLDER_SET_BY_SETUP_SCRIPT" "${MANIFESTS}/openai-backend.yaml" | \
    kubectl apply -f -
  echo "  OpenAI backend: ${GATEWAY_URL}/openai"
else
  echo "  SKIPPED — OPENAI_API_KEY not set (provide the key to enable)"
fi

log "Deploying AgentRegistry"
AR_JWT_KEY=$(openssl rand -hex 32)
helm upgrade --install agentregistry \
  "${DEMO_DIR}/agentregistry-chart/" \
  --namespace agentregistry \
  --create-namespace \
  --values "${MANIFESTS}/agentregistry-values.yaml" \
  --set config.jwtPrivateKey="${AR_JWT_KEY}" \
  --wait --timeout=180s
echo "  AgentRegistry deployed in namespace: agentregistry"

log "Waiting for all demo pods to be ready"
kubectl wait --for=condition=ready pod -l app=dex -n dex --timeout=120s
echo "  Dex: ready"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=agentregistry -n agentregistry --timeout=180s 2>/dev/null || \
  kubectl wait --for=condition=ready pod -l app=agentregistry -n agentregistry --timeout=180s 2>/dev/null || \
  echo "  AgentRegistry: check manually (label selector may vary)"

log "Seeding AgentRegistry catalog"
bash "${DEMO_DIR}/scripts/seed-agentregistry.sh" 2>/dev/null || echo "  Catalog seed skipped (seed script not ready)"

log "Demo setup complete"
echo ""
echo "  Gateway URL: ${GATEWAY_URL}"
echo "  MCP (fetch): ${GATEWAY_URL}/mcp"
echo "  MCP (docs):  ${GATEWAY_URL}/mcp/docs"
echo "  OpenAI:      ${GATEWAY_URL}/openai"
echo "  Bedrock:     ${GATEWAY_URL}/bedrock/haiku"
echo ""
echo "  Tokens sourced from: demo/.env"
echo "  Next: open UI port-forwards (see demo/ui/port-forwards.md)"
echo "  Then: run theme scripts in order — 02, 03, 04"
