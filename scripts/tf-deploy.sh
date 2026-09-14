#!/usr/bin/env bash
# Package the Lambda and terraform apply (replaces sam deploy).
# Requires the root-account profile (default bitaihang09132026) or existing AWS credentials.
#
# Env: API_KEY or INFERENCE_API_KEY (required), MODEL_ID, MODEL_MAP,
#      AWS_REGION (default us-east-1), FUNCTION_NAME (default bedrock-inference-mvp)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=aws-env.sh
source "${ROOT}/scripts/aws-env.sh"
API_KEY="${API_KEY:-${INFERENCE_API_KEY:-}}"
[[ -n "${API_KEY}" ]] || { echo "error: API_KEY or INFERENCE_API_KEY is required" >&2; exit 1; }

command -v aws >/dev/null || { echo "error: aws CLI required" >&2; exit 1; }
command -v terraform >/dev/null || { echo "error: terraform required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "error: python3 required" >&2; exit 1; }

MODEL_ID="${MODEL_ID:-amazon.nova-lite-v1:0}"
FUNCTION_NAME="${FUNCTION_NAME:-bedrock-inference-mvp}"
REGION="${AWS_REGION:-us-east-1}"
ZIP="${ROOT}/terraform/.build/lambda.zip"

if [[ "${SKIP_PACKAGE:-}" == "1" ]]; then
  [[ -f "${ZIP}" ]] || { echo "error: SKIP_PACKAGE=1 but missing ${ZIP}" >&2; exit 1; }
  echo "Using existing Lambda zip ${ZIP}"
else
  echo "Packaging Lambda…"
  "${ROOT}/scripts/package-lambda.sh" "${ZIP}"
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="bedrock-inference-tfstate-${ACCOUNT_ID}"

if ! aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "Creating Terraform state bucket ${BUCKET}…"
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
  aws s3api put-bucket-versioning --bucket "${BUCKET}" \
    --versioning-configuration Status=Enabled
  aws s3api put-public-access-block --bucket "${BUCKET}" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-encryption --bucket "${BUCKET}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
fi

if aws cloudformation describe-stacks --stack-name "${FUNCTION_NAME}" --region "${REGION}" >/dev/null 2>&1; then
  echo "Deleting SAM/CloudFormation stack ${FUNCTION_NAME} so Terraform owns the Lambda…"
  aws cloudformation delete-stack --stack-name "${FUNCTION_NAME}" --region "${REGION}"
  aws cloudformation wait stack-delete-complete --stack-name "${FUNCTION_NAME}" --region "${REGION}"
fi

cd "${ROOT}/terraform"
terraform init -input=false -reconfigure \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="key=${FUNCTION_NAME}.tfstate" \
  -backend-config="region=${REGION}"

export TF_VAR_aws_region="${REGION}"
export TF_VAR_function_name="${FUNCTION_NAME}"
export TF_VAR_lambda_zip="${ZIP}"
export TF_VAR_model_id="${MODEL_ID}"
export TF_VAR_model_map="${MODEL_MAP:-}"
export TF_VAR_api_key="${API_KEY}"
export TF_VAR_lambda_s3_bucket="${BUCKET}"
export TF_VAR_lambda_s3_key="${FUNCTION_NAME}/lambda.zip"

# SAM / Function URL creation can add these statement IDs outside Terraform.
# Import them so apply does not 409 on AddPermission.
adopt_lambda_permission() {
  local addr="$1"
  local sid="$2"
  if terraform state show -no-color "${addr}" >/dev/null 2>&1; then
    return 0
  fi
  local policy
  policy="$(aws lambda get-policy --function-name "${FUNCTION_NAME}" --region "${REGION}" --query Policy --output text 2>/dev/null || true)"
  [[ -n "${policy}" && "${policy}" != "None" ]] || return 0
  if python3 -c '
import json, sys
policy = json.loads(sys.argv[1])
stmts = policy.get("Statement", [])
if isinstance(stmts, dict):
    stmts = [stmts]
sys.exit(0 if sys.argv[2] in {s.get("Sid") for s in stmts} else 1)
' "${policy}" "${sid}"; then
    echo "Importing existing Lambda permission ${sid}…"
    terraform import -input=false -no-color "${addr}" "${FUNCTION_NAME}/${sid}"
  fi
}

adopt_lambda_permission aws_lambda_permission.function_url FunctionURLAllowPublicAccess
adopt_lambda_permission aws_lambda_permission.function_invoke FunctionURLAllowInvoke

terraform apply -input=false -auto-approve

echo
echo "Function URL:"
terraform output -raw function_url
echo
