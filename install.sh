#!/bin/bash
set -e

# This script installs all helm charts on the cluster, then applies all YAML resources defined in kustomization.yaml.

echo "=== Checking k3s is running ==="
kubectl get nodes

echo "=== Installing cert-manager via Helm ==="
kubectl create namespace cert-manager || true
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version v1.14.0 \
    --set installCRDs=true \
    --wait --timeout 300s

echo "=== Deploying resources defined in kustomization.yaml ==="
kubectl apply -k .

echo "=== Checking certificate status ==="
kubectl get cert
