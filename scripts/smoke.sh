#!/usr/bin/env bash
# Smoke-test marketplace aliases (sync + stream).
#
#   ./smoke.sh dev ministral-8b
#   ./scripts/smoke.sh ministral-8b llama4
#   FUNCTION_URL='https://..../' ./scripts/smoke.sh ministral-8b
#
# Reads the Function URL from the root account (profile bitaihang09132026).
# Curl does not need AWS creds once FUNCTION_URL is set.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=aws-env.sh
source "${ROOT}/scripts/aws-env.sh"

die() { echo "error: $*" >&2; exit 1; }

# Default set is models.json entries with "enable": true, in file order.
MODELS=()
while IFS= read -r model; do
  [[ -n "${model}" ]] && MODELS+=("${model}")
done < <(jq -r '.[] | select(.enable == true) | .alias' "${ROOT}/models/models.json")
((${#MODELS[@]} > 0)) || die "models.json has no enabled models"

if [[ -z "${FUNCTION_URL:-}" ]]; then
  command -v aws >/dev/null || die "set FUNCTION_URL, or install the aws CLI"
  FUNCTION_URL="$(aws lambda get-function-url-config \
    --region "${AWS_REGION}" \
    --function-name "${FUNCTION_NAME:-bedrock-inference-prod}" \
    --query FunctionUrl \
    --output text)"
fi

FUNCTION_URL="${FUNCTION_URL%/}/"
[[ -n "${FUNCTION_URL}" && "${FUNCTION_URL}" != "None/" && "${FUNCTION_URL}" != "/" ]] \
  || die "FUNCTION_URL is empty"
INFERENCE_API_KEY="${INFERENCE_API_KEY:-${API_KEY:-1234}}"

if [[ $# -gt 0 ]]; then
  MODELS=("$@")
fi

echo "URL  ${FUNCTION_URL}"
echo "key  ${INFERENCE_API_KEY:0:2}… (${#INFERENCE_API_KEY} chars)"
echo

chat() {
  local model="$1"
  local stream="${2:-false}"
  local extra="${3:-{}}"
  local body tmp code
  body="$(jq -nc \
    --arg model "${model}" \
    --argjson stream "${stream}" \
    --argjson extra "${extra}" \
    '{
      model: $model,
      messages: [{role: "user", content: "Say hello in one short sentence."}],
      max_tokens: 256,
      temperature: 0,
      stream: $stream
    } + $extra')"
  tmp="$(mktemp)"
  code="$(curl -sS -o "${tmp}" -w '%{http_code}' -X POST "${FUNCTION_URL}v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${INFERENCE_API_KEY}" \
    -d "${body}")"
  echo "HTTP ${code}"
  if [[ "${stream}" == "true" ]]; then
    cat "${tmp}"
  elif jq -e 'type == "object" and (.choices[0].message.content != null or .error != null or .errorType != null)' >/dev/null 2>&1 <"${tmp}"; then
    jq '{error, errorType, detail: (.detail // .errorMessage), message: .Message, model, answer: .choices[0].message.content, usage}' "${tmp}"
  else
    cat "${tmp}"
  fi
  rm -f "${tmp}"
  echo
}

for MODEL in "${MODELS[@]}"; do
  echo "=== ${MODEL} ==="
  chat "${MODEL}" false
  echo "=== ${MODEL} (stream) ==="
  chat "${MODEL}" true
done
