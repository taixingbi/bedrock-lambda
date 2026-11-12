#!/usr/bin/env bash
# Accept the Bedrock marketplace agreement for a foundation model in the root account.
#
#   ./scripts/enable-bedrock-model.sh qwen3-32b
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=aws-env.sh
source "${ROOT}/scripts/aws-env.sh"

REGION="${AWS_REGION:-us-east-1}"

die() { echo "error: $*" >&2; exit 1; }

# Friendly smoke/upload names → Bedrock foundation model ID (not a CRIS profile).
resolve_model_id() {
  case "$1" in
    qwen3-32b|qwen.qwen3-32b-v1:0|Qwen/Qwen3-32B)
      echo "qwen.qwen3-32b-v1:0"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

MODEL_ID="$(resolve_model_id "${1:-}")"
[[ -n "${MODEL_ID}" ]] || die "usage: $0 <model>"

command -v aws >/dev/null || die "aws CLI required"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "Account ${ACCOUNT_ID}  model ${MODEL_ID}  region ${REGION}"

status="$(aws bedrock get-foundation-model-availability \
  --region "${REGION}" --model-id "${MODEL_ID}" \
  --query 'agreementAvailability.status' --output text 2>/dev/null || echo UNKNOWN)"
echo "agreementAvailability=${status}"
if [[ "${status}" == "AVAILABLE" ]]; then
  echo "Already enabled."
  exit 0
fi

token="$(aws bedrock list-foundation-model-agreement-offers \
  --region "${REGION}" --model-id "${MODEL_ID}" \
  --query 'offers[0].offerToken' --output text)"
[[ -n "${token}" && "${token}" != "None" ]] \
  || die "no marketplace offer for ${MODEL_ID} (may need AWS Sales / console access)"

echo "Accepting marketplace offer for ${MODEL_ID}…"
aws bedrock create-foundation-model-agreement \
  --region "${REGION}" \
  --model-id "${MODEL_ID}" \
  --offer-token "${token}"

echo "Waiting for agreement…"
for _ in 1 2 3 4 5 6; do
  status="$(aws bedrock get-foundation-model-availability \
    --region "${REGION}" --model-id "${MODEL_ID}" \
    --query 'agreementAvailability.status' --output text)"
  echo "agreementAvailability=${status}"
  [[ "${status}" == "AVAILABLE" ]] && exit 0
  sleep 5
done
echo "Offer submitted; re-check with get-foundation-model-availability if smoke still 502s."
