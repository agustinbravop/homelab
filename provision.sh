#!/usr/bin/env bash

set -euo pipefail

# --- Dependency Check ---
if ! command -v gum >/dev/null 2>&1; then
    echo "Error: gum is not installed. Please install it to continue."
    echo "See: https://github.com/charmbracelet/gum"
    exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
    echo "Error: terraform is not installed. Please install it to continue."
    echo "See: https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli"
    exit 1
fi

if ! command -v tailscale >/dev/null 2>&1; then
    echo "Error: tailscale is not installed locally. Please install it to continue."
    echo "See: https://tailscale.com/download"
    exit 1
fi

if ! tailscale ip -4 >/dev/null 2>&1; then
    echo "Error: tailscale is installed but not connected on this machine."
    echo "Run 'tailscale up' locally, then try again."
    exit 1
fi

# --- Ask for secrets ---
gum style \
	--border normal \
	--margin "1 2" \
	--padding "1 2" \
	--border-foreground 212 "This script will provision a Hetzner server using Terraform." \
	"It will ask for your Hetzner Cloud API token and Tailscale auth key."

gum style --bold "Please provide your Hetzner Cloud API token."
echo "Get token from Hetzner Cloud Console: Project > Security > API Tokens"
HCLOUD_TOKEN=$(gum input --password --placeholder "Paste your Hetzner token here")

if [ -z "$HCLOUD_TOKEN" ]; then
    gum style --bold --foreground 212 "No API token provided. Exiting."
    exit 1
fi

gum style --bold "Please provide your Tailscale Auth Key."
echo "Get a one-off auth key from Tailscale Admin Console: Settings > Keys"
TS_AUTH_KEY=$(gum input --password --placeholder "Paste your tskey-auth-... key here")

if [ -z "$TS_AUTH_KEY" ]; then
    gum style --bold --foreground 212 "No Tailscale auth key provided. Exiting."
    exit 1
fi

# --- Run Terraform ---
echo "Running terraform init"
terraform init

echo "Running terraform apply"

# Pass the token as a variable on the command line.
# Use -auto-approve to avoid the interactive confirmation prompt from Terraform.
terraform apply -auto-approve \
  -var="hcloud_token=$HCLOUD_TOKEN" \
  -var="tailscale_auth_key=$TS_AUTH_KEY"

gum style \
	--border normal \
	--margin "1 2" \
	--padding "1 2" \
	--border-foreground 212 "✅ Provisioning complete!" \
  "kubeconfig.yaml was fetched over Tailscale and is ready to use."
