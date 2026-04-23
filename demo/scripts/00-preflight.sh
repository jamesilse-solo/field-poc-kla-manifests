#!/usr/bin/env bash
# 00-preflight.sh — validate environment before demo
# Run this first. Fixes most issues automatically.

set -euo pipefail
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; WARN=0; FAIL=0

ok()   { echo "  ✓ $*"; ((PASS++)) || true; }
warn() { echo "  ⚠ $*"; ((WARN++)) || true; }
fail() { echo "  ✗ $*"; ((FAIL++)) || true; }

echo ""
echo "═══════════════════════════════════════"
echo "  KLA Demo Preflight Check"
echo "═══════════════════════════════════════"
echo ""

# ── Required tools
echo "► Required tools"
for tool in kubectl helm aws openssl curl python3; do
  if command -v "$tool" &>/dev/null; then ok "$tool found"; else fail "$tool not found — install required"; fi
done

# ── AWS auth + EKS cluster
echo ""
echo "► AWS / EKS"
if aws sts get-caller-identity &>/dev/null; then
  ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
  ok "AWS auth valid (account: $ACCOUNT)"
else
  fail "AWS auth expired — run: aws sso login"
fi

CLUSTER="kla-agentic-cluster"
REGION="us-west-2"
if kubectl config current-context 2>/dev/null | grep -q "$CLUSTER"; then
  ok "kubectl context is $CLUSTER"
else
  warn "kubectl not pointing to $CLUSTER — updating kubeconfig"
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" 2>/dev/null && ok "kubeconfig updated" || fail "kubeconfig update failed"
fi

if kubectl get nodes --request-timeout=10s &>/dev/null; then
  NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  ok "Cluster reachable ($NODE_COUNT nodes)"
else
  fail "Cannot reach cluster — check VPN and AWS auth"
fi

# ── AgentGateway
echo ""
echo "► AgentGateway"
if kubectl get pods -n agentgateway-system --no-headers 2>/dev/null | grep -q "Running"; then
  ok "AgentGateway pods running"
else
  warn "AgentGateway pods not running — may need to wait for ArgoCD sync"
fi

GATEWAY_LB=$(kubectl get svc -n agentgateway-system -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].hostname}' 2>/dev/null | awk '{print $1}')
if [[ -n "$GATEWAY_LB" ]]; then
  ok "Gateway LoadBalancer: $GATEWAY_LB"
  echo "  export GATEWAY_URL=http://${GATEWAY_LB}"
else
  warn "Gateway LoadBalancer hostname not yet assigned"
fi

# ── License key
echo ""
echo "► Secrets"
if [[ -n "${AGENTGATEWAY_LICENSE_KEY:-}" ]]; then
  ok "AGENTGATEWAY_LICENSE_KEY set"
else
  fail "AGENTGATEWAY_LICENSE_KEY not set in environment"
fi

if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  ok "OPENAI_API_KEY set"
else
  warn "OPENAI_API_KEY not set — OpenAI backend will be skipped in setup"
fi

# ── Bedrock secret (STS credentials expire — refresh on every preflight run)
echo ""
echo "► Bedrock AWS credentials"
if kubectl get secret bedrock-secret -n agentgateway-system &>/dev/null; then
  if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
    kubectl create secret generic bedrock-secret \
      -n agentgateway-system \
      --from-literal=accessKey="${AWS_ACCESS_KEY_ID}" \
      --from-literal=secretKey="${AWS_SECRET_ACCESS_KEY}" \
      --from-literal=sessionToken="${AWS_SESSION_TOKEN:-}" \
      --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    ok "bedrock-secret refreshed with current STS credentials"
  else
    warn "AWS_ACCESS_KEY_ID not set — bedrock-secret not refreshed (Bedrock may return 403)"
  fi
else
  warn "bedrock-secret not found — Bedrock backend may not work"
fi

# ── Demo JWT key pair
echo ""
echo "► Demo JWT key pair"
KEY_FILE="${DEMO_DIR}/certs/demo-jwt.key"
if [[ ! -f "$KEY_FILE" ]]; then
  echo "  Generating demo RSA key pair..."
  openssl genrsa -out "$KEY_FILE" 2048 2>/dev/null
  ok "Generated demo-jwt.key"
else
  ok "demo-jwt.key exists"
fi

# Verify gen-token.sh works
chmod +x "${DEMO_DIR}/scripts/gen-token.sh"
if TOKEN=$("${DEMO_DIR}/scripts/gen-token.sh" alice 2>/dev/null); then
  ok "Token generation works (alice)"
  {
    echo "export ALICE_TOKEN=$TOKEN"
    echo "export BOB_TOKEN=$("${DEMO_DIR}/scripts/gen-token.sh" bob 2>/dev/null)"
    echo "export CHARLIE_TOKEN=$("${DEMO_DIR}/scripts/gen-token.sh" charlie 2>/dev/null)"
    echo "export ADMIN_TOKEN=$("${DEMO_DIR}/scripts/gen-token.sh" admin 2>/dev/null)"
    [[ -n "${GATEWAY_LB:-}" ]] && echo "export GATEWAY_URL=http://${GATEWAY_LB}"
  } > "${DEMO_DIR}/.env"
  ok "Demo tokens written to demo/.env"
else
  fail "Token generation failed"
fi

# ── Summary
echo ""
echo "═══════════════════════════════════════"
printf "  Results: %d passed, %d warnings, %d failed\n" "$PASS" "$WARN" "$FAIL"
echo "═══════════════════════════════════════"
echo ""
if [[ $FAIL -gt 0 ]]; then
  echo "Fix failures above before running 01-setup.sh"
  exit 1
elif [[ $WARN -gt 0 ]]; then
  echo "Warnings present — review before demo. Run: source demo/.env && bash demo/scripts/01-setup.sh"
else
  echo "All checks passed! Run: source demo/.env && bash demo/scripts/01-setup.sh"
fi
