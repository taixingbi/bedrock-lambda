#!/usr/bin/env bash
# Pull MiniLM weights from the shared models bucket when they are not in git.
# Uses the root-account profile (bitaihang09132026) unless AWS creds are already set.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=aws-env.sh
source "${ROOT}/scripts/aws-env.sh"
MINILM_SRC="${ROOT}/models/MiniLM-L12-H384"
MINILM_S3="${MINILM_S3_URI:-}"
REGION="${AWS_REGION:-us-east-1}"

if [[ -f "${MINILM_SRC}/model.safetensors" || -f "${MINILM_SRC}/weights.npz" ]]; then
  exit 0
fi

if ! command -v aws >/dev/null; then
  echo "error: missing MiniLM weights in ${MINILM_SRC} (aws CLI not found for S3 fallback)" >&2
  exit 1
fi

if [[ -z "${MINILM_S3}" ]]; then
  MINILM_S3="s3://$(ensure_models_bucket)/microsoft/MiniLM-L12-H384"
fi

mkdir -p "${MINILM_SRC}"
echo "Fetching MiniLM weights from ${MINILM_S3}…"
if ! aws s3 sync "${MINILM_S3}/" "${MINILM_SRC}/" --region "${REGION}" \
  --exclude "*" --include "model.safetensors" --include "weights.npz" \
  --include "tokenizer.json" --include "config.json"; then
  echo "error: could not fetch MiniLM weights from ${MINILM_S3}" >&2
  echo "error: upload weights with: ./scripts/upload-model-to-s3.sh MiniLM-L12-H384" >&2
  exit 1
fi

if [[ ! -f "${MINILM_SRC}/model.safetensors" && ! -f "${MINILM_SRC}/weights.npz" ]]; then
  echo "error: ${MINILM_S3} has no model.safetensors or weights.npz" >&2
  echo "error: run: ./scripts/upload-model-to-s3.sh MiniLM-L12-H384" >&2
  exit 1
fi
