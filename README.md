# Kubernetes Homelab

This repository contains resources and configuration for my personal Kubernetes homelab and all scripts needed to install it.

Tools:

- `k3s`.
- `kubectl`.
- `az`.

Currently the cluster is deployed on two Azure B2 VMs using free credits that I have.

## Setup

```bash
# Provision cloud resources and installs the kubernetes cluster.
bash provision.sh
# Install helm packages and applies all YAML resources defined in this repository.
bash install.sh

# Test connection to the cluster.
export KUBECONFIG=kubeconfig.yaml
kubectl get nodes

# Destroy all cloud resources.
bash destroy.sh
```

## Architecture

I'm using Cloudflare DNS for the `agusbravo.dev` domain that sends traffic to the cluster.
The Origin Certificate and Origin Key are temporarily saved to the `origin-cert.pem` and `origin-key.pem` files
to create the following secret needed by Traefik and cert-manager:

```bash
kubectl create secret tls website-tls \
  --cert=origin-cert.pem \
  --key=origin-key.pem
```

The resources in `infrastructure/` are applied at the end of `install.sh`, and the resources defined
in `apps/` are applied by ArgoCD when they're pushed to this GitHub repo (like a GitOps workflow).
