#!/usr/bin/env bash

set -euo pipefail

# This script deletes all resources created by the provisioning script.
terraform destroy
