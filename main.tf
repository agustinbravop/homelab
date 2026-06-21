terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

data "http" "cloudflare_ips" {
  url = "https://api.cloudflare.com/client/v4/ips"
}

locals {
  cloudflare_ipv4_cidrs = jsondecode(data.http.cloudflare_ips.response_body).result.ipv4_cidrs
}

variable "hcloud_token" {
  type        = string
  sensitive   = true
  description = "The Hetzner Cloud API token."
}

variable "tailscale_auth_key" {
  type        = string
  sensitive   = true
  description = "The Tailscale auth key used to join the server to your Tailnet."
}

provider "hcloud" {
  token = var.hcloud_token
}

variable "ssh_key_name" {
  type        = string
  description = "A name for the SSH key in the Hetzner Cloud project."
  default     = "homelab-key"
}

resource "hcloud_ssh_key" "default" {
  name       = var.ssh_key_name
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "hcloud_server" "homelab_server" {
  name        = "homelab-server-1"
  server_type = "cx23"
  image       = "ubuntu-22.04"
  location    = "hel1"
  ssh_keys    = [hcloud_ssh_key.default.id]
  # Inject the Tailscale auth key into the first-boot bootstrap script.
  user_data    = replace(file("${path.module}/bootstrap-server.sh"), "__TAILSCALE_AUTH_KEY__", var.tailscale_auth_key)
  firewall_ids = [hcloud_firewall.secure_firewall.id]

  lifecycle {
    ignore_changes = [
      image,
    ]
  }
}

output "ipv4_address" {
  value       = hcloud_server.homelab_server.ipv4_address
  description = "The IPv4 address of the server."
}

resource "null_resource" "kubeconfig_fetcher" {
  depends_on = [hcloud_server.homelab_server]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -e

SERVER_TS_IP=""
# Wait for the new node to appear in the local machine's Tailnet view.
for attempt in $(seq 1 60); do
  SERVER_TS_IP=$(tailscale ip -4 homelab-server-1 2>/dev/null || true)
  if [ -n "$SERVER_TS_IP" ]; then
    break
  fi
  sleep 5
done

if [ -z "$SERVER_TS_IP" ]; then
  echo "Timed out waiting for Tailscale IP for homelab-server-1"
  exit 1
fi

# Fetch kubeconfig over Tailscale so public SSH can stay closed.
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$SERVER_TS_IP "while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do sleep 5; done"
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$SERVER_TS_IP:/etc/rancher/k3s/k3s.yaml ${path.module}/kubeconfig.yaml
# Rewrite the generated kubeconfig to point kubectl at the Tailscale IP.
sed -i "s/127.0.0.1/$SERVER_TS_IP/g" ${path.module}/kubeconfig.yaml
EOT
  }
}

output "kubeconfig_file" {
  value       = "kubeconfig.yaml"
  description = "The local path to the generated kubeconfig file for your k3s cluster."
}

resource "hcloud_firewall" "secure_firewall" {
  name = "secure-homelab-firewall"
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = local.cloudflare_ipv4_cidrs
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "41641"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}
