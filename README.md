# Kubernetes Homelab

This repository installs and configures my personal Kubernetes homelab.

Tools:

- `k3s`.
- `kubectl`.
- `terraform`.
- `tailscale`.
- `gum`.

Currently the cluster is deployed on a single Hetzner Cloud `cx23` VPS.

## Setup

```bash
# Provision the Hetzner VPS with Terraform, bootstrap Tailscale + k3s, and fetch kubeconfig.yaml.
bash provision.sh

# Install Helm packages and apply all YAML resources.
bash setup-cluster.sh

# Test connection to the cluster.
export KUBECONFIG=kubeconfig.yaml
kubectl get nodes

# Destroy all Hetzner resources managed by Terraform.
bash destroy.sh
```

## Prerequisites

- `terraform` installed locally.
- `tailscale` installed locally and already connected.
- An SSH key at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`.
- A Hetzner Cloud API token.
- A one-off Tailscale auth key.

`./provision.sh` prompts for the Hetzner API token and Tailscale auth key, creates the VPS with Terraform, joins it to the Tailnet during first boot, installs k3s, and fetches `kubeconfig.yaml` over Tailscale.

## Architecture

- Cloudflare DNS sends `agusbravo.dev` traffic to the Hetzner VPS.
- The server joins my Tailnet during bootstrap, and administrative access happens over Tailscale.
- `ufw` only allows SSH and the Kubernetes API on `tailscale0`, and only allows public `443` from Cloudflare IP ranges.
- `bootstrap-server.sh` installs Tailscale first, then installs a single-node k3s cluster.
- `setup-cluster.sh` installs cert-manager, Sealed Secrets, ArgoCD, and ArgoCD Image Updater.
- The resources in `infrastructure/` are applied by `setup-cluster.sh`, and the resources in `apps/` are synced by ArgoCD.

## Notes

- `kubeconfig.yaml` is generated automatically by `./provision.sh` and is rewritten to use the server's Tailscale IP.
