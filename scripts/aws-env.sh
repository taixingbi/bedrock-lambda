#!/usr/bin/env bash
# Local AWS CLI profile. Do not override OIDC or explicit keys (GitHub Actions).
if [[ -z "${AWS_PROFILE:-}" && -z "${AWS_ACCESS_KEY_ID:-}" && -z "${AWS_WEB_IDENTITY_TOKEN_FILE:-}" ]]; then
  export AWS_PROFILE=bitaihang09132026
fi
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION}}"

# Models catalog bucket in the caller account (not the old cross-account bucket).
models_bucket() {
  if [[ -n "${MODELS_BUCKET:-}" ]]; then
    local name="${MODELS_BUCKET#s3://}"
    printf '%s' "${name%%/*}"
    return
  fi
  local account
  account="$(aws sts get-caller-identity --query Account --output text)"
  printf 'huggingface-bedrock-models-%s' "${account}"
}

ensure_models_bucket() {
  local name region
  name="$(models_bucket)"
  region="${AWS_REGION:-us-east-1}"
  # head-bucket prints JSON on stdout in newer AWS CLI; callers capture this function.
  if aws s3api head-bucket --bucket "${name}" >/dev/null 2>&1; then
    printf '%s' "${name}"
    return
  fi
  echo "Creating models bucket ${name}…" >&2
  if [[ "${region}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${name}" --region "${region}" >/dev/null
  else
    aws s3api create-bucket --bucket "${name}" --region "${region}" \
      --create-bucket-configuration "LocationConstraint=${region}" >/dev/null
  fi
  aws s3api put-bucket-versioning --bucket "${name}" \
    --versioning-configuration Status=Enabled >/dev/null
  aws s3api put-public-access-block --bucket "${name}" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
    >/dev/null
  aws s3api put-bucket-encryption --bucket "${name}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null
  printf '%s' "${name}"
}
