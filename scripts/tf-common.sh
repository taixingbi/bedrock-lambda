#!/usr/bin/env bash
# Shared Terraform setup. Sourced by scripts/tf.sh. Expects ROOT.

tf_prepare() {
  local requested="${1:-${TF_ENV:-}}"
  # shellcheck source=env-name.sh
  source "${ROOT}/scripts/env-name.sh"
  ENV="${requested}"
  FUNCTION_NAME="$(env_function_name "${ENV}")"
  REGION="${AWS_REGION:-us-east-1}"
  TF_DIR="${ROOT}/terraform/environments"
  VAR_FILE="${ENV}.tfvars"
  ZIP="${ROOT}/terraform/.build/lambda.zip"
  STATE_KEY="environments/${ENV}/terraform.tfstate"
  API_KEY="$(resolve_api_key "${ENV}")"
}

tf_export_vars() {
  local bucket="$1"
  export TF_VAR_aws_region="${REGION}"
  export TF_VAR_lambda_zip="${ZIP}"
  export TF_VAR_model_id="${MODEL_ID:-amazon.nova-lite-v1:0}"
  export TF_VAR_model_map="${MODEL_MAP:-}"
  export TF_VAR_api_key="${API_KEY}"
  export TF_VAR_lambda_s3_bucket="${bucket}"
  export TF_VAR_lambda_s3_key="${FUNCTION_NAME}/lambda.zip"
}

tf_init() {
  local bucket="$1"
  terraform -chdir="${TF_DIR}" init -input=false -reconfigure \
    -backend-config="bucket=${bucket}" \
    -backend-config="key=${STATE_KEY}" \
    -backend-config="region=${REGION}"
}

tf_ensure_state_bucket() {
  local bucket="$1"
  if aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
    return 0
  fi
  echo "Creating Terraform state bucket ${bucket}…"
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${bucket}" --region "${REGION}"
  else
    aws s3api create-bucket --bucket "${bucket}" --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
  aws s3api put-bucket-versioning --bucket "${bucket}" \
    --versioning-configuration Status=Enabled
  aws s3api put-public-access-block --bucket "${bucket}" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-encryption --bucket "${bucket}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
}

# Prod used to live at bedrock-inference-mvp.tfstate in the flat root module.
tf_seed_prod_state() {
  local bucket="$1"
  [[ "${ENV}" == "prod" ]] || return 0
  local old_key="bedrock-inference-mvp.tfstate"
  if ! aws s3api head-object --bucket "${bucket}" --key "${old_key}" >/dev/null 2>&1; then
    return 0
  fi
  tf_init "${bucket}"
  if terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q .; then
    return 0
  fi
  echo "Copying existing state ${old_key} → ${STATE_KEY}…"
  aws s3 cp "s3://${bucket}/${old_key}" "s3://${bucket}/${STATE_KEY}" --region "${REGION}"
  tf_init "${bucket}"
}

tf_ensure_zip() {
  local mode="$1"
  if [[ -f "${ZIP}" ]]; then
    return 0
  fi
  if [[ "${mode}" == "dummy" ]]; then
    mkdir -p "$(dirname "${ZIP}")"
    python3 - "${ZIP}" <<'PY'
import pathlib, sys, zipfile
path = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(path, "w") as zf:
    zf.writestr("dummy", "")
PY
    return 0
  fi
  echo "Packaging Lambda…"
  "${ROOT}/scripts/package-lambda.sh" "${ZIP}"
}

tf_account_bucket() {
  command -v aws >/dev/null || { echo "error: aws CLI required" >&2; return 1; }
  command -v terraform >/dev/null || { echo "error: terraform required" >&2; return 1; }
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  BUCKET="bedrock-inference-tfstate-${ACCOUNT_ID}"
}
