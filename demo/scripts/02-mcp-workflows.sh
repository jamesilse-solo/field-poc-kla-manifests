#!/usr/bin/env bash
# 02-mcp-workflows.sh — Theme 1: MCP Workflows & Federation
# Demonstrates: tool routing, MCP federation, multiple backends, rate limiting
# ~15-20 minutes

set -euo pipefail
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "${DEMO_DIR}/.env" ]] && source "${DEMO_DIR}/.env"
GATEWAY="${GATEWAY_URL:-http://localhost:8080}"
ALICE="${ALICE_TOKEN:-}"

step() { echo ""; echo "━━━ $* ━━━"; echo ""; }
pause() { echo ""; read -rp "  [ENTER to continue] " _; echo ""; }

# Helper: initialize an MCP session and return the session ID
# Usage: MCP_SID=$(mcp_init "${GATEWAY}/mcp" "${ALICE}")
mcp_init() {
  local endpoint="$1" token="$2"
  curl -sI "${endpoint}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"kla-demo","version":"1.0"}}}' \
    | grep -i "^mcp-session-id:" | awk '{print $2}' | tr -d '\r'
}

# ─────────────────────────────────────────────
step "2.1 — List available tools across all MCP backends"
# [MUST SHOW] This is the federation story: one gateway, many tool servers
echo "  → Initializing MCP session and listing all registered tools:"
echo ""
MCP_SID=$(mcp_init "${GATEWAY}/mcp" "${ALICE}")
echo "  Session: ${MCP_SID}"
curl -s "${GATEWAY}/mcp" \
  -H "Authorization: Bearer ${ALICE}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: ${MCP_SID}" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | python3 -m json.tool 2>/dev/null
echo ""
echo "  ↑ Each tool is registered from a different backend — gateway federates access."
pause

# ─────────────────────────────────────────────
step "2.2 — Call the 'fetch' tool (website fetcher MCP)"
echo "  → Fetching KLA's public site through the MCP gateway:"
echo ""
# Reuse or open a fresh session
MCP_SID=$(mcp_init "${GATEWAY}/mcp" "${ALICE}")
curl -s "${GATEWAY}/mcp" \
  -H "Authorization: Bearer ${ALICE}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: ${MCP_SID}" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch","arguments":{"url":"https://www.kla.com","max_length":500}}}' | \
  python3 -m json.tool 2>/dev/null | head -30
echo ""
echo "  ↑ Agent called a real web tool via the gateway — no direct internet access from agent."
pause

# ─────────────────────────────────────────────
step "2.3 — Call the Solo.io docs MCP (search.solo.io)"
# [MUST SHOW] Remote MCP federation — gateway routes to external MCP server
echo "  → Searching AgentGateway documentation via /mcp/docs:"
echo ""
DOCS_SID=$(mcp_init "${GATEWAY}/mcp/docs" "${ALICE}")
curl -s "${GATEWAY}/mcp/docs" \
  -H "Authorization: Bearer ${ALICE}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: ${DOCS_SID}" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search","arguments":{"query":"MCP federation agent routing"}}}' | \
  python3 -m json.tool 2>/dev/null | head -40
echo ""
echo "  ↑ Same gateway, different path → different MCP backend. Zero agent config change needed."
pause

# ─────────────────────────────────────────────
step "2.4 — Show tool-level rate limiting"
echo "  → The 'fetch' tool is rate-limited to 5 calls/min per user."
echo "     Sending 6 rapid calls to trigger the limit:"
echo ""
# Each call needs a fresh session (or reuse one session for all)
RATE_SID=$(mcp_init "${GATEWAY}/mcp" "${ALICE}")
for i in {1..6}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${GATEWAY}/mcp" \
    -H "Authorization: Bearer ${ALICE}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "mcp-session-id: ${RATE_SID}" \
    -d '{"jsonrpc":"2.0","id":'"$i"',"method":"tools/call","params":{"name":"fetch","arguments":{"url":"https://example.com"}}}')
  echo "    Call $i → HTTP $STATUS"
  sleep 0.3
done
echo ""
echo "  ↑ Rate limiting enforced per-tool, per-user — not just at the model level."
pause

# ─────────────────────────────────────────────
step "2.5 — Show routing config in Gloo UI"
echo "  Open http://localhost:4000 in browser"
echo "  Navigate to: Routes → See /mcp and /mcp/docs routes"
echo "  Show AgentgatewayBackend objects linking to tool servers"
echo ""
echo "  TALKING POINT: 'KLA has ~6,000 agents on Copilot Studio."
echo "  Each agent can be registered to use tools through this gateway."
echo "  No VPN, no direct tool access — all traffic flows through one control plane.'"
pause

echo ""
echo "Theme 1 complete. Next: bash demo/scripts/03-identity-auth.sh"
