#!/usr/bin/env bash
# Confirm an environment's Function URL rejects missing keys and accepts the API key.
#
#   ./scripts/validate-env.sh dev
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=aws-env.sh
source "${ROOT}/scripts/aws-env.sh"
# shellcheck source=env-name.sh
source "${ROOT}/scripts/env-name.sh"

ENV="${1:-}"
FUNCTION_NAME="$(env_function_name "${ENV}")"
REGION="${AWS_REGION:-us-east-1}"
API_KEY="$(resolve_api_key "${ENV}")"
[[ -n "${API_KEY}" ]] || { echo "error: API_KEY or INFERENCE_API_KEY is required" >&2; exit 1; }

FUNCTION_URL="$(aws lambda get-function-url-config \
  --region "${REGION}" \
  --function-name "${FUNCTION_NAME}" \
  --query FunctionUrl \
  --output text)"
FUNCTION_URL="${FUNCTION_URL%/}/"

# nova-micro, not MiniLM: the packaged classifier head is untrained and returns 502.
MODEL="${VALIDATE_MODEL:-nova-micro}"
BODY="$(jq -nc --arg model "${MODEL}" \
  '{model:$model, messages:[{role:"user", content:"hi"}], max_tokens:16}')"

code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${FUNCTION_URL}v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "${BODY}")"
[[ "${code}" == "401" || "${code}" == "403" ]] \
  || { echo "error: ${ENV} accepted an unauthenticated request (HTTP ${code})" >&2; exit 1; }

tmp="$(mktemp)"
code="$(curl -sS -o "${tmp}" -w '%{http_code}' -X POST "${FUNCTION_URL}v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d "${BODY}")"
echo "HTTP ${code}"
cat "${tmp}"
echo
rm -f "${tmp}"
[[ "${code}" == "200" ]] || { echo "error: ${ENV} validation failed" >&2; exit 1; }
echo "${ENV} validation ok"
