#!/bin/bash
set -e

echo "=== Registering Worker Clusters with ArgoCD ==="

# Get worker cluster IPs from k3d-argocd-control network
WORKER1_IP=$(docker inspect k3d-worker-1-server-0 --format '{{index .NetworkSettings.Networks "k3d-argocd-control" "IPAddress"}}')
WORKER2_IP=$(docker inspect k3d-worker-2-server-0 --format '{{index .NetworkSettings.Networks "k3d-argocd-control" "IPAddress"}}')

echo "Worker 1 IP: $WORKER1_IP"
echo "Worker 2 IP: $WORKER2_IP"

# Switch to control plane context
kubectl config use-context k3d-argocd-control

# Login to ArgoCD
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argocd login localhost:8090 --username admin --password "$ARGOCD_PASSWORD" --insecure

echo ""
echo "=== Creating Service Accounts on Worker Clusters ==="

# Create service account on worker-1
kubectl config use-context k3d-worker-1
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-manager-role
rules:
- apiGroups:
  - '*'
  resources:
  - '*'
  verbs:
  - '*'
- nonResourceURLs:
  - '*'
  verbs:
  - '*'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-manager-role
subjects:
- kind: ServiceAccount
  name: argocd-manager
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
EOF

# Wait for token to be generated
echo "Waiting for worker-1 token..."
sleep 3

# Get worker-1 token and CA
WORKER1_TOKEN=$(kubectl -n kube-system get secret argocd-manager-token -o jsonpath='{.data.token}' | base64 -d)
WORKER1_CA=$(kubectl -n kube-system get secret argocd-manager-token -o jsonpath='{.data.ca\.crt}')

# Create service account on worker-2
kubectl config use-context k3d-worker-2
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-manager-role
rules:
- apiGroups:
  - '*'
  resources:
  - '*'
  verbs:
  - '*'
- nonResourceURLs:
  - '*'
  verbs:
  - '*'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-manager-role
subjects:
- kind: ServiceAccount
  name: argocd-manager
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
EOF

# Wait for token to be generated
echo "Waiting for worker-2 token..."
sleep 3

# Get worker-2 token and CA
WORKER2_TOKEN=$(kubectl -n kube-system get secret argocd-manager-token -o jsonpath='{.data.token}' | base64 -d)
WORKER2_CA=$(kubectl -n kube-system get secret argocd-manager-token -o jsonpath='{.data.ca\.crt}')

echo ""
echo "=== Registering Clusters in ArgoCD ==="

# Switch back to control plane
kubectl config use-context k3d-argocd-control

# Register worker-1
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: worker-1-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: worker-1
  server: https://$WORKER1_IP:6443
  config: |
    {
      "bearerToken": "$WORKER1_TOKEN",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "$WORKER1_CA"
      }
    }
EOF

# Register worker-2
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: worker-2-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: worker-2
  server: https://$WORKER2_IP:6443
  config: |
    {
      "bearerToken": "$WORKER2_TOKEN",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "$WORKER2_CA"
      }
    }
EOF

echo ""
echo "=== Registered Clusters ==="
argocd cluster list

echo ""
echo "✅ Worker clusters registered successfully!"
