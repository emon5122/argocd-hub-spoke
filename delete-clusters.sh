#!/bin/bash

set -e

echo "🗑️  Deleting ArgoCD Multi-Cluster Setup..."
echo ""

# Delete all clusters
echo "Deleting worker-2..."
k3d cluster delete worker-2 || true

echo "Deleting worker-1..."
k3d cluster delete worker-1 || true

echo "Deleting argocd-control..."
k3d cluster delete argocd-control || true

# Delete network
echo ""
echo "🌐 Deleting shared network..."
docker network rm k3d-argocd-network 2>/dev/null || echo "Network already deleted or not found"

echo ""
echo "✅ All clusters deleted successfully!"
echo ""
echo "🔍 Verify: k3d cluster list"
