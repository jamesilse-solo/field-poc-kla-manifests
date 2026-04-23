#!/usr/bin/env bash
# 03-identity-auth.sh — Theme 2: Identity & Auth (Dex / Entra ID framing)
# [MUST SHOW] This is KLA's #1 requirement — agent identity via Entra ID
# Demonstrates: JWT validation, RBAC by tier, per-org isolation, agent identity
# ~15-20 minutes

set -euo pipefail
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "${DEMO_DIR}/.env" ]] && source "${DEMO_DIR}/.env"
GATEWAY="${GATEWAY_URL:-http://localhost:8080}"
ALICE="${ALICE_TOKEN:-}"
CHARLIE="${CHARLIE_TOKEN:-}"

step() { echo ""; echo "━━━ $* ━━━"; echo ""; }
pause() { echo ""; read -rp "  [ENTER to continue] " _; echo ""; }

# ─────────────────────────────────────────────
step "3.1 — Show the identity provider (Dex)"
echo "  kubectl get pods -n dex"
kubectl get pods -n dex
echo ""
echo "  TALKING POINT: 'This is Dex — an OIDC identity broker."
echo "  In production, you'd connect Azure Entra ID here."
echo "  Dex brokers Entra ID tokens and issues unified JWTs to the gateway."
echo "  Every agent call is traceable back to an identity.'"
echo ""
echo "  kubectl describe configmap dex-config -n dex | grep -A5 issuer"
kubectl get configmap dex-config -n dex -o jsonpath='{.data.config\.yaml}' | grep -A2 issuer
pause

# ─────────────────────────────────────────────
step "3.2 — Show the JWT validation policy"
echo "  kubectl get enterpriseagentgatewaypolicy gateway-jwt-auth -n agentgateway-system -o yaml"
kubectl get enterpriseagentgatewaypolicy gateway-jwt-auth -n agentgateway-system -o yaml 2>/dev/null | \
  grep -A 20 "jwtAuthentication:" || echo "  (policy applied — check Gloo UI for details)"
echo ""
echo "  TALKING POINT: 'Every request must carry a JWT from Dex / Entra ID."
echo "  The gateway validates the signature, extracts claims, and sets headers."
echo "  Downstream services see x-user-id, x-user-tier, x-org — no JWT parsing needed.'"
pause

# ─────────────────────────────────────────────
step "3.3 — Request WITHOUT a token → rejected"
echo "  → Call /bedrock/haiku with no Authorization header:"
echo ""
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  "${GATEWAY}/bedrock/haiku" \
  -H "Content-Type: application/json" \
  -d '{"model":"anthropic.claude-3-haiku-20240307-v1:0","messages":[{"role":"user","content":"hello"}],"max_tokens":10}'
echo ""
echo "  ↑ 403 — no valid token means no access. Kill switch at the identity layer."
pause

# ─────────────────────────────────────────────
step "3.4 — [MUST SHOW] Request WITH Alice's token (premium tier) → allowed"
echo "  Alice's JWT claims: org=kla, tier=premium, preferred_username=alice"
echo "  → Calling /bedrock/haiku as Alice:"
echo ""
curl -s \
  "${GATEWAY}/bedrock/haiku" \
  -H "Authorization: Bearer ${ALICE}" \
  -H "Content-Type: application/json" \
  -d '{"model":"anthropic.claude-3-haiku-20240307-v1:0","messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":50}'
echo ""
echo ""
echo "  ↑ Alice is in (premium tier, org=kla) — request passes RBAC and reaches the LLM."
pause

# ─────────────────────────────────────────────
step "3.5 — Same route, Charlie's token (free tier) — allowed but rate-limited"
echo "  Charlie's JWT claims: org=kla, tier=free, preferred_username=charlie"
echo "  → Charlie gets 50 tokens/hour vs Alice's 1000/hour:"
echo ""
curl -s \
  "${GATEWAY}/bedrock/haiku" \
  -H "Authorization: Bearer ${CHARLIE}" \
  -H "Content-Type: application/json" \
  -d '{"model":"anthropic.claude-3-haiku-20240307-v1:0","messages":[{"role":"user","content":"Say hello."}],"max_tokens":10}'
echo ""
echo ""
echo "  ↑ Both users pass the org check (jwt.org == 'kla')."
echo "  But tier is extracted to x-user-tier and drives rate limiting in the next step."
pause

# ─────────────────────────────────────────────
step "3.6 — Show claim extraction in request headers"
echo "  → Watch what headers AGW injects (via echo backend or Gloo UI tracing):"
echo ""
echo "  Open Gloo UI: http://localhost:4000"
echo "  Navigate to: Policies → gateway-jwt-auth"
echo "  Show: transformation.request.set — x-user-id, x-user-tier, x-org"
echo ""
echo "  TALKING POINT: 'When Kaustubh's team builds their agents on Copilot Studio,"
echo "  each agent call carries its Entra ID identity. The gateway extracts those claims"
echo "  and propagates them downstream — full traceability without changing agent code.'"
pause

# ─────────────────────────────────────────────
step "3.7 — [MUST SHOW] Show RBAC rule"
echo "  kubectl get enterpriseagentgatewaypolicy llm-rbac -n agentgateway-system -o yaml"
kubectl get enterpriseagentgatewaypolicy llm-rbac -n agentgateway-system -o yaml 2>/dev/null | \
  grep -A 10 "authorization:" || echo "  RBAC policy active — see Gloo UI"
echo ""
echo "  TALKING POINT: 'This single CEL expression — jwt.org == \"kla\" — ensures"
echo "  only KLA-identity tokens reach your LLMs and MCP servers."
echo "  Add jwt.team == \"approved-ai-teams\" and you have team-level agent governance.'"
pause

# ─────────────────────────────────────────────
step "3.8 — Kill switch: revoke agent access"
echo "  → If an agent is compromised, what's the kill switch?"
echo ""
echo "  For Copilot Studio agents: delete the AgentgatewayBackend:"
echo "    kubectl delete agentgatewaybackend <agent-backend> -n agentgateway-system"
echo ""
echo "  For all traffic: suspend the RBAC policy:"
echo "    kubectl patch enterpriseagentgatewaypolicy llm-rbac -n agentgateway-system \\"
echo "      --type merge -p '{\"spec\":{\"traffic\":{\"authorization\":{\"policy\":{\"matchExpressions\":[\"false\"]}}}}}'"
echo ""
echo "  For the UI: Gloo UI → Policies → click 'Disable'"
echo ""
echo "  TALKING POINT: 'This is what Kaustubh confirmed in our pre-call:"
echo "  kill switches are operational deletes, not cryptographic revocation."
echo "  kubectl delete or UI delete is sufficient for the business team.'"
pause

echo ""
echo "Theme 2 complete. Next: bash demo/scripts/04-governance-ops.sh"
