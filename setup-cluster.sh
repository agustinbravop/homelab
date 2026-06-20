#!/bin/bash
set -e

# This script installs all helm charts on the cluster, then applies all YAML resources defined in kustomization.yaml.

echo "Using ./kubeconfig.yaml to connect to the cluster..."
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

echo "Installing Sealed Secrets via Helm..."
helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
helm repo update
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --version 2.18.6 \
  --wait --timeout 120s

echo "Installing ArgoCD with Helm..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd || true
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 9.5.15 \
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

echo "Configuring Secrets"
read -rsp "Enter OPENAI_API_KEY for airlock: " OPENAI_API_KEY
echo ""

echo "Sealing airlock secret..."
kubectl create secret generic airlock \
  --namespace=airlock \
  --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
  --dry-run=client -o yaml \
  | kubeseal \
    --controller-name=sealed-secrets \
    --controller-namespace=kube-system \
    --format yaml \
    > apps/airlock/sealedsecret.yaml
unset OPENAI_API_KEY
echo "Sealed secret written to apps/airlock/sealedsecret.yaml"
echo "IMPORTANT: commit and push apps/airlock/sealedsecret.yaml so ArgoCD can apply it."

echo "Deploying resources defined in kustomization.yaml..."
kubectl apply -k .
