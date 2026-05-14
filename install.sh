#!/bin/bash
set -e

# This script installs all helm charts on the cluster, then applies all YAML resources defined in kustomization.yaml.

# Test connection to the cluster.
echo "Testing connection to the cluster..."
export KUBECONFIG=kubeconfig.yaml
kubectl get nodes

echo "Installing cert-manager via Helm..."
kubectl create namespace cert-manager || true
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version v1.14.0 \
    --set installCRDs=true \
    --wait --timeout 300s

echo "Installing ArgoCD with Helm..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd || true
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=ClusterIP \
  --set server.insecure=true

echo "Installing ArgoCD Image Updater with Helm..."
helm upgrade --install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  --version 1.1.5

echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

echo "ArgoCD installed!"
echo "Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"

echo " Deploying resources defined in kustomization.yaml "
kubectl apply -k .
