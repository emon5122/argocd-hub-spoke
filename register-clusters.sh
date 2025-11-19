#!/bin/bash

set -e

echo "🔗 Registering worker clusters with ArgoCD..."
echo ""

# Switch to control plane cluster
kubectl config use-context k3d-argocd-control

# Get worker cluster contexts
WORKER1_CONTEXT="k3d-worker-1"
WORKER2_CONTEXT="k3d-worker-2"

# Function to get the internal cluster server URL
get_internal_server_url() {
    local context=$1
    local cluster_name=$2
    # For k3d clusters, use the internal Docker network address
    echo "https://k3d-${cluster_name}-server-0:6443"
}

# Get internal server URLs
WORKER1_SERVER=$(get_internal_server_url "$WORKER1_CONTEXT" "worker-1")
WORKER2_SERVER=$(get_internal_server_url "$WORKER2_CONTEXT" "worker-2")

echo "📌 Worker 1 internal server: $WORKER1_SERVER"
echo "📌 Worker 2 internal server: $WORKER2_SERVER"
echo ""

# Function to create cluster secret
create_cluster_secret() {
    local cluster_name=$1
    local context=$2
    local server_url=$3
    
    echo "Adding cluster: $cluster_name"
    
    # Get the service account token
    kubectl config use-context "$context"
    
    # Create token for the service account (Kubernetes 1.24+)
    TOKEN=$(kubectl create token argocd-manager -n kube-system --duration=87600h)
    
    # Get CA certificate
    CA_CERT=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
    
    # Switch back to control plane
    kubectl config use-context k3d-argocd-control
    
    # Create the secret in ArgoCD namespace
    kubectl create secret generic cluster-${cluster_name} \
        -n argocd \
        --from-literal=name=${cluster_name} \
        --from-literal=server=${server_url} \
        --from-literal=config="{\"bearerToken\":\"${TOKEN}\",\"tlsClientConfig\":{\"insecure\":false,\"caData\":\"${CA_CERT}\"}}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Label the secret so ArgoCD recognizes it
    kubectl label secret cluster-${cluster_name} \
        -n argocd \
        argocd.argoproj.io/secret-type=cluster \
        --overwrite
    
    echo "✅ Cluster $cluster_name registered"
    echo ""
}

# Register worker clusters
create_cluster_secret "worker-1" "$WORKER1_CONTEXT" "$WORKER1_SERVER"
create_cluster_secret "worker-2" "$WORKER2_CONTEXT" "$WORKER2_SERVER"

echo "🎉 All worker clusters registered with ArgoCD!"
echo ""
echo "Verify in ArgoCD UI: Settings > Clusters"
echo "Or run: kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster"
