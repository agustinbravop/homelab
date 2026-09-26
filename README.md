# Kubernetes Homelab

This repository installs and configures my personal Kubernetes homelab.

Tools:

- `k3s`.
- `kubectl`.
- `terraform`.
- `tailscale`.
- `gum`.
- `prometheus`.
- `grafana`.
- `gatus`.

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

When the homelab migrates from one IP to another, we can use the following script to update DNS:

```bash
# Update Cloudflare A records under agusbravo.dev to the current Terraform public IPv4.
bash update-dns-records.sh
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
- `setup-cluster.sh` installs a resource-limited Prometheus and Grafana stack in the `monitoring` namespace.
- Blackbox Exporter checks each public application every minute for availability, latency, HTTP status, and certificate expiry.
- Traefik emits request metrics and JSON access logs; Alloy sends only those access logs to a three-day Loki store.
- `https://grafana.agusbravo.dev` has anonymous Viewer access, including queries to its Prometheus and Loki datasources; administrator access still requires the generated password.
- `https://argocd.agusbravo.dev` has anonymous access limited to viewing the public applications and logs from non-sensitive workloads; Airlock logs, repositories, clusters, accounts, terminal access, and all mutations remain unavailable.
- `https://status.agusbravo.dev` runs Gatus with five-minute checks and SQLite-backed history on a 128 MiB persistent volume.
- TLS certificates are issued by cert-manager through Cloudflare DNS-01, so the origin only needs `443` exposed to Cloudflare.
- `update-dns-records.sh` shows the current Cloudflare A records for `agusbravo.dev`, defaults the target IPv4 from `terraform output -raw ipv4_address`, and rewrites the zone's existing A records to that value.
- `setup-cluster.sh` generates `infrastructure/cert-manager/sealedsecret.yaml`; that file is a required input to `kubectl apply -k .` and should be committed once generated.
- The resources in `infrastructure/` are applied by `setup-cluster.sh`, and the resources in `apps/` are synced by ArgoCD.

## Notes

- `kubeconfig.yaml` is generated automatically by `./provision.sh` and is rewritten to use the server's Tailscale IP.
- Prometheus retains at most seven days or 4 GB of TSDB blocks, whichever limit is reached first; its WAL uses additional disk space.
