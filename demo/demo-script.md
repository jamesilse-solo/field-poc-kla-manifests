# KLA Demo — Presenter Script
**Date:** April 23, 2026 — 12:00pm PT
**Presenter:** James Ilse (solo)
**Audience:** Kaustubh Sharma + KLA extended team (Ravi from IT, identity team, business stakeholders)
**Runtime:** ~60 minutes (45 min demo + 15 min Q&A)
**Product:** AgentGateway Enterprise v2.3.0-rc.1

---

## Pre-Call Checklist (by 11:45am)
- [ ] `source demo/.env` — verify ALICE_TOKEN, GATEWAY_URL are set
- [ ] Gloo UI open: http://localhost:4000
- [ ] Grafana open: http://localhost:3000
- [ ] Terminals 1-4 from `demo/ui/port-forwards.md` running
- [ ] `bash demo/scripts/00-preflight.sh` — all green
- [ ] `bash demo/scripts/01-setup.sh` — Dex, MCP, AgentRegistry deployed
- [ ] Test: `curl -H "Authorization: Bearer $ALICE_TOKEN" $GATEWAY_URL/bedrock/haiku -d '{"model":"anthropic.claude-3-haiku-20240307-v1:0","messages":[{"role":"user","content":"ping"}],"max_tokens":5}'`
- [ ] Slack → confirm Anthony Fernando is dialed in

---

## Opening (2-3 min)

> "Thanks for joining everyone. Really glad we could get the extended team together.
> Kaustubh, looking forward to getting into the technical detail.
>
> Today's agenda: three themes, roughly 15-20 minutes each.
> One — MCP workflows and tool federation.
> Two — Identity and auth — your team's top ask.
> Three — Governance and operations.
> Then open Q&A.
>
> By the end, you'll have seen the product solve the specific problem you
> identified: safely enabling AI agent frameworks at KLA's scale."

**Key framing:** KLA has ~6,000 agents on Copilot Studio. That's the scale we're solving for.

---

## Theme 1: MCP Workflows & Federation (15-20 min)

### Setup (say while sharing screen)
> "Let me show you what we've built for this cluster. This is AgentGateway Enterprise —
> it's the control plane for your AI agents. Any agent that needs to call a tool,
> reach an LLM, or make an authenticated API call goes through here."

**Show Gloo UI → Routes** (5 seconds on this view)
> "You can see routes here for Bedrock LLMs, OpenAI, and two MCP tool servers.
> Your agents don't need to know where these are — they just talk to one gateway."

### Step 1: List MCP tools (run 02-mcp-workflows.sh step 2.1)
> "Let me ask the gateway what tools are available right now."

*[Run command — shows tools/list response]*

> "These tools come from two different servers — one is running in your cluster,
> one is the Solo.io documentation MCP on search.solo.io.
> The agent doesn't know or care where they're hosted. That's the federation story."

### Step 2: Call the fetch tool (step 2.2)
> "Watch what happens when an agent calls the 'fetch' tool — it's going through
> the gateway, which enforces auth and rate limiting before the tool ever executes."

### Step 3: [MUST SHOW] Solo.io docs MCP (step 2.3)
> "Same gateway, different path — /mcp/docs — routes to search.solo.io.
> In your environment, you could add any MCP-compatible tool server here.
> Internal tools, partner APIs, data services — all behind one control point."

**If asked about Copilot Studio integration:**
> "Copilot Studio supports MCP natively. You'd configure your studio agents
> to point to this gateway URL for tools. One config change — all 6,000 agents
> benefit from the gateway's auth and governance immediately."

### Step 4: Rate limiting (step 2.4)
> "The fetch tool is rate-limited per user — 5 calls per minute.
> Watch what happens at call 6."

*[Run — shows 429 after 5 calls]*

> "That limit is set per-tool, per-user. Not per-model, not per-hour-aggregate.
> You can tune this granularity to match KLA's actual usage patterns."

---

## Theme 2: Identity & Auth (15-20 min)
### [MUST SHOW] KLA's #1 requirement

### Setup framing
> "This is the piece your identity team cares most about.
> Every agent call needs an identity. In your case, that identity comes from Azure Entra ID."

**Show Dex pod running** (step 3.1)
> "We have Dex running as the OIDC identity broker.
> In production, you'd connect Entra ID to Dex — Dex brokers the token,
> and the gateway validates it. Your agents don't change; only the issuer config does."

**If Ravi asks about Entra ID specifically:**
> "Entra ID integration is a connector in Dex — two fields: tenant ID and client ID.
> Once that's set, any token from Entra ID is automatically validated by the gateway.
> The POC can target this as the primary auth path."

### Step: JWT policy
> "Here's the policy that validates those tokens."

*[Show auth policy YAML or Gloo UI → Policies → gateway-jwt-auth]*

> "The gateway extracts three claims from the JWT: user ID, tier, and org.
> Those become HTTP headers that your downstream services can read.
> No JWT parsing needed in your agent code."

### Step: [MUST SHOW] Request without token → blocked (step 3.3)
> "No token — let's see what happens."

*[Run — shows 403]*

> "403. The agent has no identity — it doesn't reach the LLM at all."

### Step: [MUST SHOW] Alice's token → allowed (step 3.4)
> "Now Alice. Premium tier, org=kla. Her token was issued from our demo identity provider
> — in production this comes from Entra ID."

*[Run — shows 200 with LLM response]*

> "Allowed. Alice's org claim matches the RBAC rule."

### Step: RBAC policy (step 3.7)
> "Here's that RBAC rule in full. One CEL expression."

*[Show or kubectl get]*

> "jwt.org == 'kla' — any agent presenting a KLA Entra ID token gets access.
> Add jwt.team == 'approved-ai-team' and you have team-level governance.
> This is the first time your AI agents have a security boundary that IT actually controls."

### Step: Kill switch (step 3.8)
> "Kaustubh, you asked about kill switches. Here's the answer.
> For the MCP gateway: kubectl delete or the Gloo UI delete. Sub-second."

*[Show kubectl delete command — don't actually run, show it]*

> "For the service mesh layer — that's Gloo Mesh and Istio — you'd revoke the mTLS certificate.
> The kill switch mechanism matches the threat: operational kill for the gateway,
> cryptographic revocation for inter-service mesh traffic."

---

## Theme 3: Governance & Operations (15-20 min)

### Step: Agent Registry (step 4.1)
> "The agent registry is your catalog. Who are the agents, what can they do, what limits apply?"

*[Show AgentRegistry API response or UI]*

> "Each of your 6,000 Copilot Studio agents can be registered here with its identity,
> allowed MCP servers, and rate limit tier. The registry feeds directly into the
> gateway's enforcement — no manual configuration spreadsheets."

### Step: Guardrails (step 4.2)
> "Guardrails catch what identity and RBAC can't — the content layer."

*[Run prompt injection attempt — shows block]*

> "Prompt injection — blocked. The guardrail runs before the request reaches the LLM."

### Step: PII redaction (step 4.3)
> "PII in responses — masked before the agent ever sees it."

*[Run PII request — shows [REDACTED]]*

### Step: Tiered rate limiting (step 4.4)
> "Rate limiting by tier means you can give each department a token budget.
> Engineering might get premium. A trial use case gets free. All from one config."

**Show Grafana** (step 4.5)
> "And all of this is visible here. Request rate, token usage, guardrail blocks, latency.
> This is your audit trail for AI governance — something your legal and compliance teams
> will want before you scale past 6,000 agents."

### Step: [MUST SHOW] Kill switch live (step 4.6)
> "Let me show the kill switch one more time — live this time."

*[Run kubectl delete httproute mcp-docs, confirm 404, then restore]*

> "That's it. Agent access to that tool is gone in under a second.
> Restore is a git commit and ArgoCD sync — full GitOps audit trail."

---

## Closing (2 min)

> "So — what you've seen today:
>
> MCP federation: one gateway that your 6,000 Copilot agents can use for any tool,
> any LLM, with consistent policy across all of them.
>
> Identity and auth: JWT from Entra ID, validated per-request, RBAC by org and team.
> Every agent call is traceable to an identity.
>
> Governance: guardrails, rate limiting, a registry, and kill switches —
> all managed from one control plane, all auditable.
>
> This is the 'safely turn on AI agent frameworks' story.
> The POC we're scoping for May would land this in your on-prem environment
> at actual KLA scale. Six weeks, starting with the MCP federation and identity path.
>
> Questions?"

---

## Common Q&A

**Q: How does this work with Copilot Studio specifically?**
> "Copilot Studio agents can be configured to use any MCP-compatible endpoint.
> You'd point your studio agents to $GATEWAY_URL/mcp. The gateway handles auth
> and governance — the agent just sees 'a tool server.' No Copilot Studio changes
> needed beyond that one URL."

**Q: What does the on-prem POC actually look like?**
> "Six weeks. Week 1-2: install on your EKS equivalent, get the gateway running,
> connect to your Entra ID tenant. Week 3-4: register your first set of Copilot agents,
> set up MCP routing for your internal tools. Week 5-6: tune guardrails and rate limits,
> validate with your security team. You'd have a production-ready pattern by the end."

**Q: Air-gap support?**
> "Yes. Everything here runs on-prem — no Solo.io SaaS data plane.
> The license check is the only outbound call, and we have an air-gap license mode
> for fully isolated environments. That's a TFIA discussion item for May 21."

**Q: What about the existing Istio service mesh?**
> "AgentGateway and Gloo Mesh are complementary. AgentGateway handles north-south
> AI traffic — agent to tool, agent to LLM. Gloo Mesh handles east-west service mesh —
> service to service. They share the same control plane. You'd run both."

**Q: Pricing?**
> "Anthony has the numbers — I'll hand that to him. The opportunity we're scoping
> is around $125K for Istio plus AgentGateway Enterprise."

---

## Timing Guide

| Time | Section |
|------|---------|
| 12:00 | Opening (2 min) |
| 12:02 | Theme 1: MCP Workflows (18 min) |
| 12:20 | Theme 2: Identity & Auth (18 min) |
| 12:38 | Theme 3: Governance (12 min) |
| 12:50 | Closing + Q&A (10 min) |
| 1:00  | Hard stop |

---

## Key Names to Drop

- **Kaustubh Sharma** — internal champion, coordinating identity/IT/business. He asked about Entra ID.
- **Ravi** (IT) — likely attending, focus on operational kill switches and IT governance angle
- **6,000 agents** on Copilot Studio — use this number. It validates the scale story.
- **TFIA May 21** at KLA HQ Building 8, Milpitas — end on this as the concrete next step.
- **Azure Entra ID** — call it "Entra ID" not "Azure AD" — KLA's language

---
*Generated by demo-agent for KLA — April 22, 2026*
