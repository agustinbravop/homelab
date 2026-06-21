#!/bin/bash
set -euo pipefail

# This script bootstraps a fresh server with Tailscale, k3s, and the final firewall rules.
# It runs on first boot via Terraform on the provisioned server, NOT on your local machine.

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y curl jq ufw

# Install Tailscale from the official bootstrap script.
curl -fsSL https://tailscale.com/install.sh | sh
# Join the server to the Tailnet during first boot.
# Note: __TAILSCALE_AUTH_KEY__ gets replaced by terraform apply.
tailscale up --auth-key="__TAILSCALE_AUTH_KEY__" --hostname=homelab-server-1

TAILSCALE_IP=$(tailscale ip -4)

# Expose the Kubernetes API cert on the server's Tailscale IP.
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --write-kubeconfig-mode 644 --tls-san ${TAILSCALE_IP}" sh -

# Wait until k3s has written the kubeconfig we fetch later.
while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do
  sleep 5
done

# Reset UFW so the final policy is fully defined here.
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
# Only allow SSH and the Kubernetes API over Tailscale.
ufw allow in on tailscale0 proto tcp to any port 22
ufw allow in on tailscale0 proto tcp to any port 6443
# Pull the current Cloudflare IPv4 ranges from the official API before opening 443.
for cloudflare_ip in $(curl -fsSL https://api.cloudflare.com/client/v4/ips | jq -r '.result.ipv4_cidrs[]'); do
  ufw allow from "$cloudflare_ip" to any port 443 proto tcp
done
ufw --force enable
