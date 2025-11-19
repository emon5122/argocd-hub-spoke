#!/bin/bash

set -e

echo "🚀 Creating k3d clusters for ArgoCD Agent Pull Model Architecture"
echo ""

# Create Docker network first
echo "🌐 Creating shared Docker network (k3d-argocd-network)..."
docker network create k3d-argocd-network 2>/dev/null || echo "Network already exists, continuing..."

# Create control plane cluster
echo ""
echo "📦 Creating control plane cluster (argocd-control)..."
k3d cluster create --config k3d-control-plane.yaml

# Create worker cluster 1
echo ""
echo "📦 Creating worker cluster 1 (worker-1)..."
k3d cluster create --config k3d-worker-1.yaml

# Create worker cluster 2
echo ""
echo "📦 Creating worker cluster 2 (worker-2)..."
k3d cluster create --config k3d-worker-2.yaml

echo ""
echo "✅ All clusters created successfully!"
echo ""
echo "📋 Cluster Information:"
echo "┌─────────────────┬──────────────────┬────────────────────────────┐"
echo "│ Cluster         │ Role             │ Network Connectivity       │"
echo "├─────────────────┼──────────────────┼────────────────────────────┤"
echo "│ argocd-control  │ Control Plane    │ Receives agent connections │"
echo "│ worker-1        │ Worker (Agent)   │ Connects TO control        │"
echo "│ worker-2        │ Worker (Agent)   │ Connects TO control        │"
echo "└─────────────────┴──────────────────┴────────────────────────────┘"
echo ""
echo "🔒 Network Architecture:"
echo "  ✅ Workers CAN reach control plane (pull model)"
echo "  ❌ Control plane CANNOT reach workers (no direct access)"
echo ""
echo "🔍 Verify clusters: k3d cluster list"
echo "🔍 Verify network: docker network inspect k3d-argocd-network"
echo ""
echo "📝 Next step: Run './setup-argocd-agent.sh' to install ArgoCD Agent"
