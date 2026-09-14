#!/usr/bin/env bash
# Tear down the inference Lambda in the root account.
#
# Usage:
#   ./scripts/tf-destroy.sh
#
# Env: AWS_REGION (default us-east-1), FUNCTION_NAME (default bedrock-inference-mvp)
#      API_KEY / INFERENCE_API_KEY only needed if terraform still evaluates them
#      (defaults to 1234). AWS_PROFILE defaults to bitaihang09132026.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=aws-env.sh
source "${ROOT}/scripts/aws-env.sh"

TF_DIR="${ROOT}/terraform"
REGION="${AWS_REGION:-us-east-1}"
FUNCTION_NAME="${FUNCTION_NAME:-bedrock-inference-mvp}"
ZIP="${ROOT}/terraform/.build/lambda.zip"
API_KEY="${API_KEY:-${INFERENCE_API_KEY:-1234}}"

die() { echo "error: $*" >&2; exit 1; }
command -v aws >/dev/null || die "aws CLI required"
command -v terraform >/dev/null || die "terraform required"
command -v python3 >/dev/null || die "python3 required"

ensure_zip() {
  if [[ -f "${ZIP}" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "${ZIP}")"
  python3 - "${ZIP}" <<'PY'
import pathlib, sys, zipfile
path = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(path, "w") as zf:
    zf.writestr("dummy", "")
PY
}

export_lambda_vars() {
  local bucket="$1"
  export TF_VAR_aws_region="${REGION}"
  export TF_VAR_function_name="${FUNCTION_NAME}"
  export TF_VAR_lambda_zip="${ZIP}"
  export TF_VAR_model_id="${MODEL_ID:-amazon.nova-lite-v1:0}"
  export TF_VAR_model_map="${MODEL_MAP:-}"
  export TF_VAR_api_key="${API_KEY}"
  export TF_VAR_lambda_s3_bucket="${bucket}"
  export TF_VAR_lambda_s3_key="${FUNCTION_NAME}/lambda.zip"
}

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="bedrock-inference-tfstate-${ACCOUNT_ID}"
echo "Destroy ${FUNCTION_NAME} in root account ${ACCOUNT_ID} (${REGION}), profile ${AWS_PROFILE:-env}…"

ensure_zip

if ! aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "No state bucket ${BUCKET}; nothing to destroy."
  exit 0
fi

export_lambda_vars "${BUCKET}"
cd "${TF_DIR}"
terraform init -input=false -reconfigure \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="key=${FUNCTION_NAME}.tfstate" \
  -backend-config="region=${REGION}"
terraform destroy -input=false -auto-approve

echo
echo "Destroy complete (${FUNCTION_NAME} in ${ACCOUNT_ID})."
