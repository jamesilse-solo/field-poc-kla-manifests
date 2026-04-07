# KLA AgentGateway Enterprise Demo

## Cluster

| | |
|---|---|
| **Cluster** | `kla-agentic-cluster` |
| **Region** | us-west-2 |
| **Nodes** | 2x t3.large (on-demand) |
| **K8s Version** | 1.35 |
| **AWS Profile** | `Field-Engineering-Team-986112284769` |

```bash
aws eks update-kubeconfig --region us-west-2 --name kla-agentic-cluster
```

## AgentGateway Enterprise

- **Version**: v2.3.0-rc.1
- **License**: `$AGENTGATEWAY_LICENSE_KEY` (expires 2049)
- **Gateway URL**: `http://<GATEWAY_HOSTNAME>:8080`

Get the gateway hostname:
```bash
kubectl get svc -n agentgateway-system \
  --selector=gateway.networking.k8s.io/gateway-name=agentgateway-proxy \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
```

### Pods (agentgateway-system)

| Pod | Purpose |
|---|---|
| agentgateway-proxy (x2) | Data plane proxies |
| enterprise-agentgateway | Controller |
| ext-auth-service | API key / JWT authentication |
| ext-cache (Redis) | Auth + rate limit caching |
| rate-limiter | Token-based rate limiting |
| solo-enterprise-ui | Gloo UI (traces) |
| solo-enterprise-telemetry-collector | OTel collector |
| clickhouse | Trace storage |

## ArgoCD

ArgoCD manages the full stack via an app-of-apps pattern.

### Access

```bash
# Port-forward to access the UI
kubectl port-forward svc/argocd-server -n argocd 8443:443
# Open https://localhost:8443
```

| | |
|---|---|
| **Username** | admin |
| **Password** | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" \| base64 -d` |

ArgoCD is also exposed through the AgentGateway (secured with API key auth):
```
http://<GATEWAY_HOSTNAME>:8080/argocd
```

### App-of-Apps Structure

| Application | Type | What it manages |
|---|---|---|
| `kla-agentgateway-demo` | Root (app-of-apps) | Syncs `manifests/argocd/` to deploy all child apps |
| `agw-crds` | Helm (OCI) | Enterprise AgentGateway CRDs |
| `agw-controller` | Helm (OCI) | Enterprise AgentGateway controller (license patched via kubectl) |
| `agw-config` | Git manifests | EnterpriseAgentgatewayParameters, Gateway, HTTPRoutes, auth policies |
| `agw-management` | Helm (OCI) | Gloo UI + telemetry + ClickHouse |
| `agw-monitoring-manifests` | Git manifests | PodMonitor for Prometheus scraping |
| `prometheus-grafana` | Helm | kube-prometheus-stack (Prometheus + Grafana) |

**Note**: The license key is not stored in git. It was patched into the `agw-controller` Application:
```bash
kubectl -n argocd patch application agw-controller --type merge \
  -p "{\"spec\":{\"source\":{\"helm\":{\"parameters\":[{\"name\":\"licensing.licenseKey\",\"value\":\"$AGENTGATEWAY_LICENSE_KEY\",\"forceString\":true}]}}}}"
```

## API Key Authentication

All routes through the gateway are secured with API key auth via ext-auth.

### Demo Keys

| Header | Key | User | Tier |
|---|---|---|---|
| `x-api-key` | `sk-kla-demo-admin-2026` | admin | admin |
| `x-api-key` | `sk-kla-demo-user-2026` | kla-user | standard |

### Testing

```bash
export GW=$(kubectl get svc -n agentgateway-system \
  --selector=gateway.networking.k8s.io/gateway-name=agentgateway-proxy \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

# Without key (401)
curl -i "http://$GW:8080/argocd"

# With key (works)
curl -i -H "x-api-key: sk-kla-demo-admin-2026" "http://$GW:8080/argocd"
```

### Adding New API Keys

Create a new Secret in `manifests/base/apikey-auth.yaml` with the label `api-key-group: kla-demo`, push to git, and ArgoCD will sync it.

## Monitoring

### Grafana

```bash
kubectl port-forward svc/grafana-prometheus -n monitoring 3000:3000
# Open http://localhost:3000
```

| | |
|---|---|
| **Username** | admin |
| **Password** | prom-operator |
| **Dashboard** | AgentGateway Overview (pre-loaded) |

### Gloo UI (Traces)

```bash
kubectl port-forward svc/solo-enterprise-ui -n agentgateway-system 4000:80
# Open http://localhost:4000
```

## Git Repo

https://github.com/jamesilse-solo/field-poc-kla-manifests

```
manifests/
  argocd/                  # ArgoCD Application definitions (app-of-apps)
    application.yaml       # Root app
    agw-crds.yaml          # CRDs helm app
    agw-controller.yaml    # Controller helm app
    agw-config.yaml        # K8s manifests app (base/)
    agw-management.yaml    # Gloo UI helm app
    agw-monitoring-manifests.yaml  # K8s manifests app (monitoring/)
    prometheus-grafana.yaml        # Prometheus stack helm app
  base/                    # Declarative K8s manifests
    enterprise-agentgateway-params.yaml
    gateway.yaml
    argocd-route.yaml
    apikey-auth.yaml
  monitoring/
    pod-monitor.yaml
terraform/                 # EKS cluster IaC
```

## Teardown

```bash
cd ~/field-poc-kla/terraform
terraform destroy
```
