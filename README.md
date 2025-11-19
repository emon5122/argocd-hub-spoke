# ArgoCD Agent - Pull Model Architecture 🚀

This project demonstrates the **ArgoCD Agent** architecture using a **pull model** where worker clusters connect to the control plane, but the control plane **cannot** connect back to the workers.

## 🎯 Architecture Overview

```
    ┌─────────────────────┐
    │  Control Plane      │  ← ArgoCD UI + Agent Principal
    │  (argocd-control)   │     (NO outbound access to workers!)
    └─────────────────────┘
              ▲     ▲
              │     │
        PULL  │     │  PULL
              │     │
      ┌───────┘     └────────┐
      │                      │
  ┌───────┐              ┌───────┐
  │Worker1│              │Worker2│  ← Agents initiate connections
  │(Agent)│              │(Agent)│     (Workers connect TO hub)
  └───────┘              └───────┘
```

### Key Points

✅ **Workers PULL from control plane** - Agents initiate connections  
✅ **Control plane NEVER connects to workers** - No direct access needed  
✅ **No cluster credentials on control plane** - Enhanced security  
✅ **Perfect for edge/restricted networks** - Firewall-friendly  

## 📋 Components

| Cluster | Role | Components | Network Access |
|---------|------|------------|----------------|
| `argocd-control` | Control Plane | ArgoCD + Agent Principal | Receives agent connections |
| `worker-1` | Worker | ArgoCD Agent | Connects TO control plane |
| `worker-2` | Worker | ArgoCD Agent | Connects TO control plane |

## 🚀 Quick Start

### Prerequisites

- Docker
- k3d (v5.x or later)
- kubectl
- bash

### 1. Create Clusters

```bash
chmod +x *.sh
./create-clusters.sh
```

This creates:
- 3 k3d clusters on a shared Docker network
- Control plane exposed on ports 8080/8443/8444
- Workers isolated (no inbound access)

### 2. Install ArgoCD Agent

```bash
./setup-argocd-agent.sh
```

This installs:
- **Control Plane**: ArgoCD + Agent Principal (from official manifests)
- **Worker-1**: ArgoCD Agent (connects to principal)
- **Worker-2**: ArgoCD Agent (connects to principal)

### 3. Access ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 --context k3d-argocd-control
```

Visit: https://localhost:8080

Get credentials:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" --context k3d-argocd-control | base64 -d
```

### 4. Deploy Applications

```bash
./deploy-apps.sh
```

This deploys nginx to both worker clusters via ArgoCD Applications.

## 🔍 Verification

### Check Control Plane

```bash
kubectl get pods -n argocd --context k3d-argocd-control
```

Expected pods:
- `argocd-server-*`
- `argocd-repo-server-*`
- `argocd-application-controller-*`
- `argocd-agent-principal-*` ← Agent Principal

### Check Worker-1 Agent

```bash
kubectl get pods -n argocd-agent --context k3d-worker-1
```

Expected: `argocd-agent-*` (connected to principal)

### Check Worker-2 Agent

```bash
kubectl get pods -n argocd-agent --context k3d-worker-2
```

Expected: `argocd-agent-*` (connected to principal)

### Check Applications

```bash
kubectl get applications -n argocd --context k3d-argocd-control
```

Expected:
- `nginx-worker-1` (deployed to worker-1)
- `nginx-worker-2` (deployed to worker-2)

### Check Deployed Apps

```bash
# Worker-1
kubectl get pods -n nginx-app --context k3d-worker-1

# Worker-2
kubectl get pods -n nginx-app --context k3d-worker-2
```

## 🌐 Access Applications

### Worker-1 Nginx

```bash
kubectl port-forward -n nginx-app svc/nginx 8081:80 --context k3d-worker-1
```

Visit: http://localhost:8081

### Worker-2 Nginx

```bash
kubectl port-forward -n nginx-app svc/nginx 8082:80 --context k3d-worker-2
```

Visit: http://localhost:8082

## 🧹 Cleanup

```bash
./delete-clusters.sh
```

## 📚 How It Works

### Installation Sources

This project uses the **official ArgoCD Agent manifests**:

- **Control Plane**: `kubectl apply -k https://github.com/argoproj-labs/argocd-agent/install/kubernetes/principal`
- **Agents**: `kubectl apply -k https://github.com/argoproj-labs/argocd-agent/install/kubernetes/agent`

### Network Architecture

- All 3 clusters share the `k3d-argocd-network` Docker network
- Workers can resolve `k3d-argocd-control-server-0:8443` (principal endpoint)
- Control plane **cannot** initiate connections to workers
- Agents maintain persistent gRPC connections to principal

### Application Deployment Flow

1. Create `Application` resource on control plane (in ArgoCD)
2. Agent principal receives the application definition
3. Agents pull the definition from principal
4. Agents deploy to their local clusters
5. Agents report status back to principal
6. Status visible in ArgoCD UI

## 🎓 Key Differences from Traditional ArgoCD

| Feature | Traditional ArgoCD | ArgoCD Agent (This Setup) |
|---------|-------------------|---------------------------|
| Connection Direction | Control → Workers | Workers → Control |
| Cluster Credentials | Stored on control plane | Not needed on control plane |
| Network Requirements | Control needs access to all workers | Workers need access to control |
| Security | Control has full cluster access | Zero-trust, no direct access |
| Use Case | Same datacenter/VPC | Edge, air-gapped, multi-cloud |

## 📖 Learn More

- [ArgoCD Agent GitHub](https://github.com/argoproj-labs/argocd-agent)
- [ArgoCD Agent Documentation](https://argocd-agent.readthedocs.io/latest/)
- [Getting Started Guide](https://argocd-agent.readthedocs.io/latest/getting-started/kubernetes/)

## 🔧 Troubleshooting

### Agents not connecting?

Check agent logs:
```bash
kubectl logs -n argocd-agent -l app.kubernetes.io/name=argocd-agent --context k3d-worker-1
```

### Applications not syncing?

Check principal logs:
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-agent-principal --context k3d-argocd-control
```

### Network connectivity issues?

Verify Docker network:
```bash
docker network inspect k3d-argocd-network
```

All 3 cluster nodes should be on this network.

## ⚠️ Important Notes

- **ArgoCD Agent is approaching GA** but still in active development
- This is a **learning/demo setup** - adapt for production
- The pull model is perfect for edge, air-gapped, and multi-cloud scenarios
- No cluster credentials are stored on the control plane (enhanced security)

## 🎯 Next Steps

1. Explore ArgoCD UI and observe pull-based synchronization
2. Try modifying application manifests in `apps/` directories
3. Experiment with ApplicationSets for multi-cluster deployments
4. Test agent resilience by stopping/starting agents

---

**Built with ❤️ using [ArgoCD Agent](https://github.com/argoproj-labs/argocd-agent)**
