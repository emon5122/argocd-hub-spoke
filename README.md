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

### 2. Create ArgoCD Namespace

Create the ArgoCD namespace on the control plane cluster:

```bash
kubectl create namespace argocd --context k3d-argocd-control
```

### 3. Install ArgoCD Principal on Control Plane

Install a customized ArgoCD instance that excludes components that will run on workload clusters:

```bash
# Apply the principal-specific Argo CD configuration
kubectl apply -n argocd \
  -k 'https://github.com/argoproj-labs/argocd-agent/install/kubernetes/argo-cd/principal?ref=v0.5.0' \
  --context k3d-argocd-control
```

This configuration includes:

✅ **argocd-server** (API and UI)  
✅ **argocd-dex-server** (SSO, if needed)  
✅ **argocd-redis** (state storage)  
✅ **argocd-repo-server** (Git repository access)  
✅ **argocd-notifications-controller** (notifications)  
❌ **argocd-application-controller** (runs on workload clusters only)  
❌ **argocd-applicationset-controller** (not yet supported)

**Critical Component Placement:**
- Control plane runs the UI, API, and Git repo access
- Workers run the application controllers that deploy resources

### 3.1 Configure Apps-in-Any-Namespace

Update the ArgoCD server configuration to enable apps-in-any-namespace:

```bash
# Patch the configmap to enable apps in any namespace
kubectl create configmap argocd-cmd-params-cm \
  --from-literal=application.namespaces='*' \
  -n argocd --context k3d-argocd-control \
  --dry-run=client -o yaml | kubectl apply -f - --context k3d-argocd-control

# Restart the server to apply changes
kubectl rollout restart deployment argocd-server -n argocd --context k3d-argocd-control
```

This allows ArgoCD applications to be created in any namespace, not just the `argocd` namespace.

### 3.2 Initialize PKI (Certificate Authority)

Initialize the PKI for secure communication between the principal and agents:

```bash
# Initialize the PKI and create the Certificate Authority
~/bin/argocd-agentctl pki init \
  --principal-context k3d-argocd-control \
  --principal-namespace argocd
```

This creates a Certificate Authority (CA) and stores it in the secret `argocd-agent-ca` in the `argocd` namespace. The CA will be used to sign certificates for secure gRPC communication between the principal and agents.

### 3.3 Generate Principal Certificates

Generate TLS certificates for the principal's gRPC server and resource proxy:

```bash
# Get your host IP address (replace with your actual IP)
HOST_IP=$(hostname -I | cut -d' ' -f1)

# Issue gRPC server certificate (agents connect to this)
~/bin/argocd-agentctl pki issue principal \
  --principal-context k3d-argocd-control \
  --principal-namespace argocd \
  --ip 127.0.0.1,${HOST_IP} \
  --dns localhost,k3d-argocd-control-server-0,argocd-agent-principal-server.argocd.svc.cluster.local \
  --upsert

# Issue resource proxy certificate (Argo CD connects to this)
~/bin/argocd-agentctl pki issue resource-proxy \
  --principal-context k3d-argocd-control \
  --principal-namespace argocd \
  --ip 127.0.0.1,${HOST_IP} \
  --dns localhost,argocd-agent-resource-proxy.argocd.svc.cluster.local \
  --upsert
```

This creates two secrets:
- `argocd-agent-principal-tls`: Certificate for agent-to-principal communication
- `argocd-agent-resource-proxy-tls`: Certificate for ArgoCD-to-resource-proxy communication

### 3.4 Create JWT Signing Key

Generate a JWT signing key for agent authentication:

```bash
~/bin/argocd-agentctl jwt create-key \
  --principal-context k3d-argocd-control \
  --principal-namespace argocd \
  --upsert
```

This creates the secret `argocd-agent-jwt` which contains the JWT signing key used to authenticate agents when they connect to the principal.

### 3.5 Install Principal Component

Deploy the ArgoCD Agent Principal:

```bash
# Deploy the principal component
kubectl apply -n argocd \
  -k 'https://github.com/argoproj-labs/argocd-agent/install/kubernetes/principal?ref=v0.5.0' \
  --context k3d-argocd-control
```

### 3.6 Configure Principal

Verify and configure the principal settings:

```bash
# Check the principal authentication configuration (should output: mtls:CN=([^,]+))
kubectl get configmap argocd-agent-params -n argocd --context k3d-argocd-control \
  -o jsonpath='{.data.principal\.auth}'

# Update principal configuration to allow agents in specific namespace
kubectl get configmap argocd-agent-params -n argocd --context k3d-argocd-control -o yaml > /tmp/agent-params.yaml
sed -i 's/principal.allowed-namespaces: .*/principal.allowed-namespaces: argocd-agent/' /tmp/agent-params.yaml
kubectl apply -f /tmp/agent-params.yaml --context k3d-argocd-control

# Restart the principal to apply changes
kubectl rollout restart deployment argocd-agent-principal -n argocd --context k3d-argocd-control
```

### 3.7 Expose Principal Service

The principal's gRPC service needs to be accessible from worker clusters:

```bash
# Change service type to NodePort for k3d environment
kubectl get svc argocd-agent-principal -n argocd --context k3d-argocd-control -o yaml > /tmp/principal-svc.yaml
sed -i 's/type: ClusterIP/type: NodePort/' /tmp/principal-svc.yaml
kubectl apply -f /tmp/principal-svc.yaml --context k3d-argocd-control
```

### 3.8 Verify Principal Installation

```bash
# Check pod status
kubectl get pods -n argocd --context k3d-argocd-control | grep principal

# Check service
kubectl get svc argocd-agent-principal -n argocd --context k3d-argocd-control

# Check logs
kubectl logs -n argocd deployment/argocd-agent-principal --context k3d-argocd-control
```

Expected log output should show:
- `Starting argocd-agent-principal`
- `gRPC server listening on :8443`
- `Resource proxy started on :9090`

### 4. Setup Worker Clusters

#### 4.1 Choose Agent Mode

There are two agent modes available:

- **Managed Mode**: Principal manages Applications, agent executes them (simpler for getting started)
- **Autonomous Mode**: Agent manages its own Applications, principal provides observability

For this setup:
- **Worker-1**: Managed mode (applications managed by control plane)
- **Worker-2**: Autonomous mode (applications managed locally)

#### 4.2 Create Namespaces on Workers

```bash
# Create namespace on worker-1
kubectl create namespace argocd --context k3d-worker-1

# Create namespace on worker-2
kubectl create namespace argocd --context k3d-worker-2
```

#### 4.3 Install ArgoCD on Worker Clusters

**Worker-1 (Managed Mode):**

```bash
kubectl apply -n argocd \
  -k 'https://github.com/argoproj-labs/argocd-agent/install/kubernetes/argo-cd/agent-managed?ref=v0.5.0' \
  --context k3d-worker-1
```

This configuration includes:
- ✅ **argocd-application-controller** (reconciles applications)
- ✅ **argocd-repo-server** (Git access)
- ✅ **argocd-redis** (local state)
- ❌ **argocd-server** (runs on control plane only)
- ❌ **argocd-applicationset-controller** (managed agents don't create their own ApplicationSets)

**Worker-2 (Autonomous Mode):**

```bash
kubectl apply -n argocd \
  -k 'https://github.com/argoproj-labs/argocd-agent/install/kubernetes/argo-cd/agent-autonomous?ref=v0.5.0' \
  --context k3d-worker-2
```

This configuration includes:
- ✅ **argocd-application-controller** (reconciles applications)
- ✅ **argocd-applicationset-controller** (manages ApplicationSets locally)
- ✅ **argocd-repo-server** (Git access)
- ✅ **argocd-redis** (local state)
- ❌ **argocd-server** (runs on control plane only)

**Why Application Controller Runs on Workers:**

The `argocd-application-controller` runs on workload clusters because it needs direct access to the Kubernetes API to create, update, and delete resources. The `argocd-agent` facilitates communication between the control plane and these controllers, enabling centralized management while maintaining local execution.

### 4.4 Create and Connect Agents

#### 4.4.1 Create Agent Configurations

```bash
# Create agent configuration for worker-1
~/bin/argocd-agentctl agent create worker-1-agent \
  --principal-context k3d-argocd-control \
  --principal-namespace argocd \
  --resource-proxy-server 10.27.27.11:9090

# Create agent configuration for worker-2
~/bin/argocd-agentctl agent create worker-2-agent \
  --principal-context k3d-argocd-control \
  --principal-namespace argocd \
  --resource-proxy-server 10.27.27.11:9090
```

#### 4.4.2 Issue Agent Client Certificates

```bash
# Issue certificate for worker-1 agent
~/bin/argocd-agentctl pki issue agent worker-1-agent \
  --principal-context k3d-argocd-control \
  --agent-context k3d-worker-1 \
  --agent-namespace argocd \
  --upsert

# Issue certificate for worker-2 agent
~/bin/argocd-agentctl pki issue agent worker-2-agent \
  --principal-context k3d-argocd-control \
  --agent-context k3d-worker-2 \
  --agent-namespace argocd \
  --upsert
```

#### 4.4.3 Propagate Certificate Authority to Agents

```bash
# Propagate CA to worker-1
~/bin/argocd-agentctl pki propagate \
  --principal-context k3d-argocd-control \
  --principal-namespace argocd \
  --agent-context k3d-worker-1 \
  --agent-namespace argocd

# Propagate CA to worker-2
~/bin/argocd-agentctl pki propagate \
  --principal-context k3d-argocd-control \
  --principal-namespace argocd \
  --agent-context k3d-worker-2 \
  --agent-namespace argocd
```

#### 4.4.4 Verify Certificate Installation

```bash
# Verify worker-1 certificates
kubectl get secret argocd-agent-client-tls -n argocd --context k3d-worker-1
kubectl get secret argocd-agent-ca -n argocd --context k3d-worker-1

# Verify worker-2 certificates
kubectl get secret argocd-agent-client-tls -n argocd --context k3d-worker-2
kubectl get secret argocd-agent-ca -n argocd --context k3d-worker-2
```

#### 4.4.5 Create Agent Namespace on Principal

For managed agents, create a namespace on the principal where the agent's Applications will be managed:

```bash
# Create namespace for worker-1 managed agent
kubectl create namespace worker-1-agent --context k3d-argocd-control
```

Note: Worker-2 runs in autonomous mode, so it doesn't need a namespace on the principal.

#### 4.4.6 Deploy Agents

```bash
# Deploy agent on worker-1
kubectl apply -n argocd \
  -k 'https://github.com/argoproj-labs/argocd-agent/install/kubernetes/agent?ref=v0.5.0' \
  --context k3d-worker-1

# Deploy agent on worker-2
kubectl apply -n argocd \
  -k 'https://github.com/argoproj-labs/argocd-agent/install/kubernetes/agent?ref=v0.5.0' \
  --context k3d-worker-2
```

#### 4.4.7 Configure Agent Connections

Get the principal's LoadBalancer IP address:

```bash
# Get principal LoadBalancer IP
PRINCIPAL_IP=$(kubectl get svc argocd-agent-principal -n argocd --context k3d-argocd-control -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Principal IP: $PRINCIPAL_IP"
```

Configure worker-1 agent (managed mode):

```bash
kubectl create configmap argocd-agent-params \
  --from-literal=agent.server.address='172.19.0.3' \
  --from-literal=agent.server.port='443' \
  --from-literal=agent.mode='managed' \
  --from-literal=agent.creds='mtls:any' \
  -n argocd --context k3d-worker-1 \
  --dry-run=client -o yaml | kubectl apply -f - --context k3d-worker-1

# Restart the agent
kubectl rollout restart deployment argocd-agent-agent -n argocd --context k3d-worker-1
```

Configure worker-2 agent (autonomous mode):

```bash
kubectl create configmap argocd-agent-params \
  --from-literal=agent.server.address='172.19.0.3' \
  --from-literal=agent.server.port='443' \
  --from-literal=agent.mode='autonomous' \
  --from-literal=agent.creds='mtls:any' \
  -n argocd --context k3d-worker-2 \
  --dry-run=client -o yaml | kubectl apply -f - --context k3d-worker-2

# Restart the agent
kubectl rollout restart deployment argocd-agent-agent -n argocd --context k3d-worker-2
```

Note: We use the LoadBalancer IP on port 443, which the k3d loadbalancer forwards to the principal service.

**Network Configuration:**
- Control plane LoadBalancer IP: Get via `kubectl get svc argocd-agent-principal -n argocd --context k3d-argocd-control -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`
- Worker agents connect via Docker network to this LoadBalancer IP on port 443
- The k3d proxy LoadBalancer forwards to the principal service

### 5. Verification

#### 5.1 Check Agent Connection

```bash
# Check worker-1 agent logs
kubectl logs -n argocd deployment/argocd-agent-agent --context k3d-worker-1

# Check worker-2 agent logs  
kubectl logs -n argocd deployment/argocd-agent-agent --context k3d-worker-2
```

Expected output:
```
INFO Starting argocd-agent (agent) v0.5.0 (ns=argocd, mode=managed, auth=mtls)
INFO Authentication successful
INFO Connected to argocd-agent-principal v0.5.0
```

#### 5.2 Verify Principal Recognizes Agents

```bash
# Check principal logs
kubectl logs -n argocd deployment/argocd-agent-principal --context k3d-argocd-control
```

Expected output:
```
INFO Agent worker-1-agent connected successfully
INFO Creating a new queue pair for client worker-1-agent
INFO Agent worker-2-agent connected successfully
INFO Creating a new queue pair for client worker-2-agent
```

#### 5.3 List Connected Agents

```bash
~/bin/argocd-agentctl agent list \
  --principal-context k3d-argocd-control \
  --principal-namespace argocd
```

### 6. Access ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 --context k3d-argocd-control
```

Visit: https://localhost:8080

Get credentials:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" --context k3d-argocd-control | base64 -d
```

### 5. Deploy Applications

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

## Step 6: Verification

### 6.1 Check Agent Connection

#### Worker-1 Agent Logs

```bash
kubectl logs -n argocd deployment/argocd-agent-agent --context k3d-worker-1 --tail=20
```

**Expected output:**

```
time="2025-11-19T22:32:01Z" level=info msg="Loading root CA certificate from secret argocd/argocd-agent-ca"
time="2025-11-19T22:32:01Z" level=info msg="Loading client TLS certificate from secret argocd/argocd-agent-client-tls"
time="2025-11-19T22:32:01Z" level=info msg="Starting argocd-agent (agent) v0.5.0 (ns=argocd, allowed_namespaces=[], mode=managed, auth=mtls)" module=Agent
time="2025-11-19T22:32:01Z" level=info msg="Authentication successful" module=Connector
time="2025-11-19T22:32:01Z" level=info msg="Connected to argocd-agent-0.5.0" module=Connector
time="2025-11-19T22:32:01Z" level=info msg="Starting event writer" clientAddr="172.19.0.3:8444" module=EventWriter
time="2025-11-19T22:32:01Z" level=info msg="Starting to receive events from event stream" direction=recv module=StreamEvent serverAddr="172.19.0.3:8444"
time="2025-11-19T22:32:01Z" level=info msg="Starting to send events to event stream" direction=send module=StreamEvent serverAddr="172.19.0.3:8444"
```

Key success indicators:
- ✅ `"Authentication successful"`
- ✅ `"Connected to argocd-agent-0.5.0"`
- ✅ `"Starting event writer"`
- ✅ `"Starting to receive/send events from event stream"`

#### Worker-2 Agent Logs

```bash
kubectl logs -n argocd deployment/argocd-agent-agent --context k3d-worker-2 --tail=20
```

**Expected output:**

```
time="2025-11-19T22:32:02Z" level=info msg="Starting argocd-agent (agent) v0.5.0 (ns=argocd, allowed_namespaces=[], mode=autonomous, auth=mtls)" module=Agent
time="2025-11-19T22:32:02Z" level=info msg="Authentication successful" module=Connector
time="2025-11-19T22:32:02Z" level=info msg="Connected to argocd-agent-0.5.0" module=Connector
time="2025-11-19T22:32:02Z" level=info msg="Starting to send events to event stream" direction=send module=StreamEvent serverAddr="172.19.0.3:8444"
time="2025-11-19T22:32:02Z" level=info msg="Starting to receive events from event stream" direction=recv module=StreamEvent serverAddr="172.19.0.3:8444"
time="2025-11-19T22:32:02Z" level=info msg="Starting event writer" clientAddr="172.19.0.3:8444" module=EventWriter
```

### 6.2 Verify Principal Recognizes Agents

Check principal logs:

```bash
kubectl logs -n argocd deployment/argocd-agent-principal --context k3d-argocd-control --tail=20
```

**Expected output:**

```
time="2025-11-19T22:32:01Z" level=info msg="Matched client cert subject to agent name" client="10.42.0.1:20253" module=AuthHandler
time="2025-11-19T22:32:01Z" level=info msg="An agent connected to the subscription stream" client=worker-1-agent method=Subscribe
time="2025-11-19T22:32:01Z" level=info msg="Starting event writer" clientAddr="10.42.0.1:20253" module=EventWriter
time="2025-11-19T22:32:02Z" level=info msg="Matched client cert subject to agent name" client="10.42.0.1:61585" module=AuthHandler
time="2025-11-19T22:32:02Z" level=info msg="An agent connected to the subscription stream" client=worker-2-agent method=Subscribe
time="2025-11-19T22:32:11Z" level=info msg="Starting event writer" clientAddr="10.42.0.1:61585" module=EventWriter
```

Key success indicators:
- ✅ `"An agent connected to the subscription stream" client=worker-1-agent`
- ✅ `"An agent connected to the subscription stream" client=worker-2-agent`
- ✅ `"Matched client cert subject to agent name"` for both agents

### 6.3 List Connected Agents

```bash
~/bin/argocd-agentctl agent list \
  --principal-context k3d-argocd-control \
  --principal-namespace argocd
```

**Expected output:**

```
worker-1-agent
worker-2-agent
```

### 6.4 Network Configuration Summary

The successful agent connection uses the following network path:

**Agent → Principal Connection Path:**
1. Agent pods connect to `172.19.0.3:8444` (k3d server node IP)
2. k3d has `8444:8444` port mapping with `nodeFilters: server:0`
3. k3s klipper-lb pod listens on hostPort 8444
4. klipper-lb forwards to Kubernetes service `argocd-agent-principal:8444`
5. Service routes to principal pod container port `8443`

**Key Configuration:**
- **Server IP:** `172.19.0.3` (k3d-argocd-control-server-0)
- **LoadBalancer IP:** `172.19.0.4` (k3d-argocd-control-serverlb)
- **Agent Connection:** `172.19.0.3:8444`
- **Principal Certificate SANs:** `127.0.0.1`, `10.27.27.11`, `172.19.0.4`, `172.19.0.3`
- **Authentication Method:** `mtls:any`
- **Principal Pod:** Listens on port `8443`
- **Service Mapping:** Port `8444` → TargetPort `8443`

**ConfigMap Parameters (both workers):**
- `agent.server.address`: `172.19.0.3`
- `agent.server.port`: `8444`
- `agent.creds`: `mtls:any`
- `agent.tls.secret-name`: `argocd-agent-client-tls`
- `agent.tls.root-ca-secret-name`: `argocd-agent-ca`
- `agent.namespace`: `argocd`
- `agent.mode`: `managed` (worker-1) / `autonomous` (worker-2)

**Troubleshooting Tips:**

If agents fail to connect, verify:
1. Principal certificate includes all necessary IP SANs
2. Agent configmap has `agent.creds='mtls:any'` (not just `mtls`)
3. Agent connects to server IP `172.19.0.3:8444` (not LoadBalancer IP)
4. Principal service exposes port 8444 mapping to targetPort 8443
5. k3d port mapping `8444:8444` is configured with `server:0` nodeFilter

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
