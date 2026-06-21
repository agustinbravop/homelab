#!/usr/bin/env bash

set -euo pipefail

# This script installs the cluster add-ons and applies the repo kustomization.
# It also regenerates the sealed secrets required by ArgoCD and cert-manager.

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG="${ROOT}/kubeconfig.yaml"
AIRLOCK_SECRET="${ROOT}/apps/airlock/sealedsecret.yaml"
CERT_MANAGER_SECRET="${ROOT}/infrastructure/cert-manager/sealedsecret.yaml"

# Dependency check
for cmd in gum kubectl helm kubeseal; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed."
    exit 1
  fi
done

if [ ! -f "$KUBECONFIG" ]; then
  echo "Error: ${KUBECONFIG} not found. Run 'bash provision.sh' first."
  exit 1
fi

if [ ! -d "${ROOT}/apps/airlock" ] || [ ! -d "${ROOT}/infrastructure/cert-manager" ]; then
  echo "Error: run this script from the repo checkout."
  exit 1
fi

export KUBECONFIG

gum style \
  --border normal \
  --margin "1 2" \
  --padding "1 2" \
  --border-foreground 212 "This script installs cert-manager, Sealed Secrets, ArgoCD, and ArgoCD Image Updater." \
  "It regenerates ${AIRLOCK_SECRET#"${ROOT}/"} and ${CERT_MANAGER_SECRET#"${ROOT}/"}."

kubectl get nodes >/dev/null
gum style --bold "Cluster reachable via ${KUBECONFIG#"${ROOT}/"}."

echo "Adding Helm repositories"
helm repo add jetstack https://charts.jetstack.io
helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

if ! kubectl get ns cert-manager >/dev/null 2>&1; then
  kubectl create ns cert-manager
fi

if ! kubectl get ns argocd >/dev/null 2>&1; then
  kubectl create ns argocd
fi

echo "Installing cert-manager"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.14.0 \
  --set installCRDs=true \
  --wait \
  --timeout 300s

echo "Installing Sealed Secrets"
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --version 2.18.6 \
  --wait \
  --timeout 120s

echo "Installing ArgoCD"
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 9.5.15 \
  --set server.service.type=ClusterIP \
  --set server.insecure=true \
  --wait \
  --timeout 300s

echo "Installing ArgoCD Image Updater"
helm upgrade --install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  --version 1.1.5 \
  --wait \
  --timeout 300s

kubectl wait \
  --for=condition=ready \
  pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd \
  --timeout=300s

trap 'unset OPENAI_API_KEY CLOUDFLARE_API_TOKEN' EXIT

gum style --bold "Enter the secrets to seal into Git-managed manifests."
OPENAI_API_KEY="$(gum input --password --placeholder "OPENAI_API_KEY for airlock")"
CLOUDFLARE_API_TOKEN="$(gum input --password --placeholder "Cloudflare API token for cert-manager")"
if [ -z "$OPENAI_API_KEY" ]; then
  echo "Error: OPENAI_API_KEY is required."
  exit 1
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  echo "Error: Cloudflare API token is required."
  exit 1
fi

if ! kubectl get ns airlock >/dev/null 2>&1; then
  kubectl create ns airlock
fi

echo "Sealing airlock secret"
kubectl create secret generic airlock \
  --namespace=airlock \
  --from-literal="OPENAI_API_KEY=$OPENAI_API_KEY" \
  --dry-run=client -o yaml \
  | kubeseal \
    --controller-name=sealed-secrets \
    --controller-namespace=kube-system \
    --format yaml \
    > "$AIRLOCK_SECRET"

echo "Sealing cert-manager secret"
kubectl create secret generic cloudflare-api-token \
  --namespace=cert-manager \
  --from-literal="api-token=$CLOUDFLARE_API_TOKEN" \
  --dry-run=client -o yaml \
  | kubeseal \
    --controller-name=sealed-secrets \
    --controller-namespace=kube-system \
    --format yaml \
    > "$CERT_MANAGER_SECRET"

echo "Applying kustomization"
kubectl apply -k "$ROOT"

gum style \
  --border normal \
  --margin "1 2" \
  --padding "1 2" \
  --border-foreground 212 "Cluster setup complete." \
  "ArgoCD password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d" \
  "Commit ${AIRLOCK_SECRET#"${ROOT}/"} and ${CERT_MANAGER_SECRET#"${ROOT}/"}."
