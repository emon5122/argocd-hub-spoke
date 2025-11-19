# ArgoCD Multi-Cluster Setup

This project demonstrates a multi-cluster GitOps setup using ArgoCD with k3d.

## Architecture

- **Control Plane Cluster** (`argocd-control`): Hosts the ArgoCD server and controllers
- **Worker Cluster 1** (`worker-1`): Managed by ArgoCD for deployments
- **Worker Cluster 2** (`worker-2`): Managed by ArgoCD for deployments

## Prerequisites

- Docker
- k3d (v5.x or later)
- kubectl

## Quick Start

### Create Clusters

```bash
# Make scripts executable (on Linux/WSL)
chmod +x create-clusters.sh delete-clusters.sh

# Create all three clusters
./create-clusters.sh
```

### Delete Clusters

```bash
./delete-clusters.sh
```

## Cluster Configuration

Each cluster is configured with:
- 1 server node (no agent nodes for simplicity)
- Traefik disabled (we'll use our own ingress)
- Unique port mappings to avoid conflicts

### Port Mappings

| Cluster | HTTP | HTTPS |
|---------|------|-------|
| argocd-control | 8080 | 8443 |
| worker-1 | 8081 | 8444 |
| worker-2 | 8082 | 8445 |

## Next Steps

1. Install ArgoCD on the control plane cluster
2. Register worker clusters with ArgoCD
3. Deploy sample applications across clusters
