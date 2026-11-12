#!/usr/bin/env bash
# fmt + validate. No AWS credentials required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v terraform >/dev/null || { echo "error: terraform required" >&2; exit 1; }

echo "terraform fmt…"
terraform fmt -check -recursive "${ROOT}/terraform"

echo "terraform validate…"
terraform -chdir="${ROOT}/terraform" init -backend=false -input=false
terraform -chdir="${ROOT}/terraform" validate
