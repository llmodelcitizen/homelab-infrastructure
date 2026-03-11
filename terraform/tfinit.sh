#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
terraform init -backend-config=backend.tfbackend "$@"
