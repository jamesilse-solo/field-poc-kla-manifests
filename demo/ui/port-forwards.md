# Port-Forward Reference — KLA Demo

Run these in separate terminals before the demo. Keep them running throughout.

## Terminal Setup (open 4 terminals)

### Terminal 1 — Gateway (for curl commands)
```bash
# Use port-forward for reliable local access (LB DNS may fluctuate)
kubectl port-forward -n agentgateway-system svc/agentgateway-proxy 8080:8080 &
export GATEWAY_URL=http://localhost:8080
echo "Gateway: $GATEWAY_URL"
```

### Terminal 2 — Gloo Management UI (port 4000)
```bash
kubectl port-forward -n agentgateway-system \
  svc/agentgateway-management-ui 4000:4000
# Open: http://localhost:4000
```

### Terminal 3 — Grafana (port 3000)
```bash
kubectl port-forward -n monitoring \
  svc/prometheus-stack-grafana 3000:80 2>/dev/null || \
kubectl port-forward -n agentgateway-system \
  svc/grafana 3000:3000
# Open: http://localhost:3000 (admin / admin)
```

### Terminal 4 — AgentRegistry (port 12121)
```bash
kubectl port-forward -n agentregistry \
  svc/agentregistry 12121:12121
# API: http://localhost:12121
```

## Quick UI Navigation

| UI | URL | Show during |
|----|-----|-------------|
| Gloo Management | http://localhost:4000 | Theme 1 (routes), Theme 2 (policies), Theme 3 (guardrails) |
| Grafana | http://localhost:3000 | Theme 3 (token usage, latency) |
| AgentRegistry | http://localhost:12121 | Theme 3 (catalog) |

## Gloo UI Click Path (for Theme 2)

1. **Routes** → shows /mcp, /mcp/docs, /bedrock/*, /openai routes
2. **Backends** → shows all AgentgatewayBackend objects (Bedrock, OpenAI, MCP servers)
3. **Policies** → gateway-jwt-auth (JWT validation), llm-rbac (authorization)
4. **Guardrails** → kla-bedrock-guardrails (prompt injection, PII)
5. **Rate Limits** → kla-tiered-rate-limits (free/standard/premium/admin)

## Backup: Text-based verification
```bash
# If UI isn't working, show config via kubectl
kubectl get agentgatewaybackend -n agentgateway-system
kubectl get enterpriseagentgatewaypolicy -n agentgateway-system
kubectl get ratelimitconfig -n agentgateway-system
kubectl get httproute -n agentgateway-system
```
