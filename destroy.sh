#!/usr/bin/env bash

set -euo pipefail

# This script destroys the Terraform-managed homelab resources.
terraform destroy
