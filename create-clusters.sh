#!/bin/bash

set -e

echo "🚀 Creating ArgoCD Multi-Cluster Setup..."
echo ""

# Create control plane cluster
echo "📦 Creating control plane cluster (argocd-control)..."
k3d cluster create --config k3d-control-plane.yaml

# Create worker cluster 1
echo "📦 Creating worker cluster 1 (worker-1)..."
k3d cluster create --config k3d-worker-1.yaml

# Create worker cluster 2
echo "📦 Creating worker cluster 2 (worker-2)..."
k3d cluster create --config k3d-worker-2.yaml

echo ""
echo "✅ All clusters created successfully!"
echo ""
echo "📋 Cluster Information:"
echo "  • Control Plane: k3d-argocd-control (ports: 8080:80, 8443:443)"
echo "  • Worker 1: k3d-worker-1 (ports: 8081:80, 8444:443)"
echo "  • Worker 2: k3d-worker-2 (ports: 8082:80, 8445:443)"
echo ""
echo "🔍 Verify clusters with: k3d cluster list"
echo "🔍 View kubeconfig contexts: kubectl config get-contexts"
