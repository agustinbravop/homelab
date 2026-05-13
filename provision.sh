# This script provisions MS Azure VMs using a student subscription.
# Azure CLI required. Can be installed with `brew install azure-cli`.
# See: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli.

# Log in with a student email and pick the "Azure for students" subscription.
az login

# Register Azure providers that are not included by default in the student subscription.
export RESOURCE_GROUP="website"
export LOCATION="eastus"
export SERVER_VM="k3s-server"
export AGENT_VM="k3s-agent"

# Create a resource group for all resources.
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create a server VM and an agent VM following a simple k3s architecture.
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $SERVER_VM \
  --image Ubuntu2404 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $AGENT_VM \
  --image Ubuntu2404 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys

# Open ports for HTTP, Kubernetes API, and k3s supervisor.
az vm open-port --resource-group $RESOURCE_GROUP --name $SERVER_VM --port 6443,10250
az vm open-port --resource-group $RESOURCE_GROUP --name $AGENT_VM --port 80,443,6443,10250

# Install k3s on the server (--tls-san allows access from public IP).
SERVER_PUBLIC_IP=$(az vm show --name $SERVER_VM --resource-group $RESOURCE_GROUP --show-details --query "publicIps" --output tsv)
az vm run-command invoke \
    --resource-group $RESOURCE_GROUP \
    --name $SERVER_VM \
    --command-id RunShellScript \
    --scripts "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --tls-san ${SERVER_PUBLIC_IP}' sh -"

# Get the server token needed by the agent.
K3S_TOKEN=$(az vm run-command invoke \
    --resource-group $RESOURCE_GROUP \
    --name $SERVER_VM \
    --command-id RunShellScript \
    --scripts "sudo cat /var/lib/rancher/k3s/server/node-token" \
    --query "value[0].message" \
    --output tsv \
    | head -n -3 | tail -n +3) # Leave only stdout

SERVER_PRIVATE_IP=$(az vm show --name $SERVER_VM --resource-group $RESOURCE_GROUP --show-details --query "privateIps" --output tsv)

# Install k3s on the agent.
az vm run-command invoke \
    --resource-group $RESOURCE_GROUP \
    --name $AGENT_VM \
    --command-id RunShellScript \
    --scripts "curl -sfL https://get.k3s.io | K3S_URL=https://$SERVER_PRIVATE_IP:6443 K3S_TOKEN=$K3S_TOKEN sh -"

# kubectl is required. Can be installed with brew install kubectl.
# See: https://kubernetes.io/docs/tasks/tools/#kubectl.

# Get the server kubeconfig.yaml (admin superuser).
az vm run-command invoke \
    --resource-group $RESOURCE_GROUP \
    --name $SERVER_VM \
    --command-id RunShellScript \
    --scripts "sudo cat /etc/rancher/k3s/k3s.yaml | sudo base64" \
    --query "value[0].message" \
    --output tsv \
    | head -n -3 \
    | tail -n +3 \
    | base64 --decode \
    | sed "s/127.0.0.1/$SERVER_PUBLIC_IP/" > kubeconfig.yaml

# Test connection to the cluster.
export KUBECONFIG=kubeconfig.yaml
kubectl get nodes
