#!/usr/bin/env bash
# Publish this commit's Lambda zip to one environment.
# Infra must already have created the function.
#
#   ./scripts/app-deploy.sh dev
#   ./scripts/app-deploy.sh prod
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=aws-env.sh
source "${ROOT}/scripts/aws-env.sh"
# shellcheck source=env-name.sh
source "${ROOT}/scripts/env-name.sh"

ENV="${1:-}"
FUNCTION_NAME="$(env_function_name "${ENV}")"
REGION="${AWS_REGION:-us-east-1}"
ZIP="${ROOT}/terraform/.build/lambda.zip"

command -v aws >/dev/null || { echo "error: aws CLI required" >&2; exit 1; }

if [[ "${SKIP_PACKAGE:-}" != "1" || ! -f "${ZIP}" ]]; then
  echo "Packaging Lambda…"
  "${ROOT}/scripts/package-lambda.sh" "${ZIP}"
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="bedrock-inference-tfstate-${ACCOUNT_ID}"
KEY="${FUNCTION_NAME}/releases/${GITHUB_SHA:-local}/lambda.zip"

echo "Uploading ${ENV} code to s3://${BUCKET}/${KEY}…"
aws s3 cp "${ZIP}" "s3://${BUCKET}/${KEY}" --region "${REGION}"

echo "Updating ${FUNCTION_NAME} in account ${ACCOUNT_ID}…"
aws lambda update-function-code \
  --region "${REGION}" \
  --function-name "${FUNCTION_NAME}" \
  --s3-bucket "${BUCKET}" \
  --s3-key "${KEY}" >/dev/null
aws lambda wait function-updated --region "${REGION}" --function-name "${FUNCTION_NAME}"

aws lambda get-function-url-config \
  --region "${REGION}" \
  --function-name "${FUNCTION_NAME}" \
  --query FunctionUrl \
  --output text
