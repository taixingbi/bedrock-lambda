#!/usr/bin/env bash
# Upload / register a model in the shared Bedrock models bucket.
#
# Usage:
#   ./scripts/upload-model-to-s3.sh nova-pro
#   ./scripts/upload-model-to-s3.sh llama
#   ./scripts/upload-model-to-s3.sh gpt-oss
#   ./scripts/upload-model-to-s3.sh deepseek
#   ./scripts/upload-model-to-s3.sh qwen3-next-80b-a3b
#   ./scripts/upload-model-to-s3.sh ministral-3b
#   ./scripts/upload-model-to-s3.sh gemma-3-4b
#   ./scripts/upload-model-to-s3.sh qwen3-32b
#   ./scripts/upload-model-to-s3.sh MiniLM-L12-H384
#
# Env overrides:
#   BUCKET      default s3://huggingface-bedrock-models-<account-id>
#   AWS_REGION  default us-east-1
#   MODEL_ID, MODEL_NAME, US_PROFILE, GLOBAL_PROFILE
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=aws-env.sh
source "${ROOT}/scripts/aws-env.sh"

BUCKET="${BUCKET:-s3://$(ensure_models_bucket)}"
REGION="${AWS_REGION:-us-east-1}"

# Catalog: key1|key2|...|display|provider|name|id|aliases|profiles
# profiles: none | us | us+global  (last 6 fields are fixed; earlier fields are lookup keys)
MARKETPLACE_MODELS=(
  'nova-lite|nova-lite-v1|Amazon Nova Lite|amazon|nova-lite-v1|amazon.nova-lite-v1:0|nova-lite, amazon.nova-lite-v1:0|none'
  'nova-pro|nova-pro-v1|Amazon Nova Pro|amazon|nova-pro-v1|amazon.nova-pro-v1:0|nova-pro, amazon.nova-pro-v1:0|us'
  'llama|llama3.3|llama-3.3-70b|Meta Llama 3.3 70B Instruct|meta|llama3-3-70b-instruct|meta.llama3-3-70b-instruct-v1:0|llama, llama3.3, llama-3.3-70b, us.meta.llama3-3-70b-instruct-v1:0|us'
  'llama4|llama4-maverick|llama-4-maverick|Meta Llama 4 Maverick 17B Instruct|meta|llama4-maverick-17b-instruct|meta.llama4-maverick-17b-instruct-v1:0|llama4, llama4-maverick, llama-4-maverick, us.meta.llama4-maverick-17b-instruct-v1:0|us'
  'llama4-scout|llama-4-scout|Meta Llama 4 Scout 17B Instruct|meta|llama4-scout-17b-instruct|meta.llama4-scout-17b-instruct-v1:0|llama4-scout, llama-4-scout, us.meta.llama4-scout-17b-instruct-v1:0|us'
  'gpt-oss|gpt-oss-120b|OpenAI GPT-OSS 120B|openai|gpt-oss-120b|openai.gpt-oss-120b-1:0|gpt-oss, gpt-oss-120b, openai.gpt-oss-120b-1:0|none'
  'gpt-oss-20b|OpenAI GPT-OSS 20B|openai|gpt-oss-20b|openai.gpt-oss-20b-1:0|gpt-oss-20b, openai.gpt-oss-20b-1:0|none'
  'gpt-oss-safeguard-20b|OpenAI GPT-OSS Safeguard 20B|openai|gpt-oss-safeguard-20b|openai.gpt-oss-safeguard-20b|gpt-oss-safeguard-20b, openai.gpt-oss-safeguard-20b|none'
  'gpt-oss-safeguard|gpt-oss-safeguard-120b|OpenAI GPT-OSS Safeguard 120B|openai|gpt-oss-safeguard-120b|openai.gpt-oss-safeguard-120b|gpt-oss-safeguard, gpt-oss-safeguard-120b, openai.gpt-oss-safeguard-120b|none'
  'deepseek|deepseek-v3.2|DeepSeek V3.2|deepseek|deepseek-v3.2|deepseek.v3.2|deepseek, deepseek-v3.2, deepseek.v3.2|none'
  'deepseek-r1|DeepSeek R1|deepseek|deepseek-r1-v1|deepseek.r1-v1:0|deepseek-r1, us.deepseek.r1-v1:0|us'
  'qwen3-next-80b-a3b|Qwen3 Next 80B A3B|qwen|qwen3-next-80b-a3b|qwen.qwen3-next-80b-a3b|qwen3-next-80b-a3b, qwen.qwen3-next-80b-a3b|none'
  'ministral-3b|ministral-3-3b|Ministral 3 3B|mistral|ministral-3-3b-instruct|mistral.ministral-3-3b-instruct|ministral-3b, ministral-3-3b, mistral.ministral-3-3b-instruct|none'
  'ministral-8b|ministral-3-8b|Ministral 3 8B|mistral|ministral-3-8b-instruct|mistral.ministral-3-8b-instruct|ministral-8b, ministral-3-8b, mistral.ministral-3-8b-instruct|none'
  'ministral-14b|ministral-3-14b|Ministral 3 14B|mistral|ministral-3-14b-instruct|mistral.ministral-3-14b-instruct|ministral-14b, ministral-3-14b, mistral.ministral-3-14b-instruct|none'
  'gemma-3-4b|gemma-3-4b-it|Gemma 3 4B IT|google|gemma-3-4b-it|google.gemma-3-4b-it|gemma-3-4b, gemma-3-4b-it, google.gemma-3-4b-it|none'
  'gemma-3-12b|gemma-3-12b-it|Gemma 3 12B IT|google|gemma-3-12b-it|google.gemma-3-12b-it|gemma-3-12b, gemma-3-12b-it, google.gemma-3-12b-it|none'
  'gemma-3-27b|gemma-3-27b-it|Gemma 3 27B IT|google|gemma-3-27b-it|google.gemma-3-27b-it|gemma-3-27b, gemma-3-27b-it, google.gemma-3-27b-it|none'
  'qwen3-32b|Qwen3 32B|qwen|qwen3-32b|qwen.qwen3-32b-v1:0|qwen3-32b, qwen.qwen3-32b-v1:0, Qwen/Qwen3-32B|none'
)

usage() {
  cat <<'EOF'
Usage: ./scripts/upload-model-to-s3.sh <model> [options]

Models:
  nova-lite / nova-pro / llama / llama4 / llama4-maverick / llama4-scout
  gpt-oss / gpt-oss-20b / gpt-oss-safeguard-20b / gpt-oss-safeguard-120b / deepseek / deepseek-r1
  qwen3-next-80b-a3b / qwen3-32b
  ministral-3b / ministral-8b / ministral-14b
  gemma-3-4b / gemma-3-12b / gemma-3-27b
  minilm-l12-h384 / MiniLM-L12-H384
                  Sync models/MiniLM-L12-H384 weights (in-Lambda classifier)

Env:
  BUCKET, AWS_REGION, MODEL_ID, MODEL_NAME, US_PROFILE, GLOBAL_PROFILE
EOF
}

die() { echo "error: $*" >&2; exit 1; }

require_aws() {
  command -v aws >/dev/null || die "aws CLI required"
}

# Register a Bedrock marketplace model catalog entry (no weights).
upload_marketplace_manifest() {
  require_aws

  local display_name="$1"
  local provider="$2"
  local model_name="$3"
  local model_id="$4"
  local aliases="$5"
  local us_profile="${6:-}"
  local global_profile="${7-}"
  local prefix="${provider}/${model_name}"

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN

  local profiles
  if [[ -n "${us_profile}" && -n "${global_profile}" ]]; then
    profiles=$(cat <<EOF
  "inference_profile_ids": {
    "in_region": "${model_id}",
    "us": "${us_profile}",
    "global": "${global_profile}"
  },
EOF
)
  elif [[ -n "${us_profile}" ]]; then
    profiles=$(cat <<EOF
  "inference_profile_ids": {
    "in_region": "${model_id}",
    "us": "${us_profile}"
  },
EOF
)
  else
    profiles=$(cat <<EOF
  "inference_profile_ids": {
    "in_region": "${model_id}"
  },
EOF
)
  fi

  local manifest="${tmp}/model-manifest.json"
  cat >"${manifest}" <<EOF
{
  "name": "${display_name}",
  "provider": "${provider}",
  "type": "bedrock-marketplace",
  "model_id": "${model_id}",
${profiles}
  "region": "${REGION}",
  "s3_prefix": "${BUCKET}/${prefix}/",
  "note": "Marketplace model — enable access in the Bedrock console. Weights are not stored in this bucket. Request model aliases: ${aliases}."
}
EOF

  local dest="${BUCKET}/${prefix}/model-manifest.json"
  echo "Uploading manifest → ${dest}"
  aws s3 cp "${manifest}" "${dest}" --region "${REGION}"

  echo
  echo "Done. Catalog entry: ${BUCKET}/${prefix}/"
  echo
  echo "Next:"
  echo "  1. Bedrock console → Model access → enable ${display_name} (${model_id})"
  echo "  2. Redeploy — request \"model\": \"$(echo "${aliases}" | cut -d, -f1 | tr -d ' ')\" (Converse; no Custom Model Import)"
  echo
  aws s3 ls "${BUCKET}/${prefix}/" --region "${REGION}"
}

# Parse catalog row: keys|display|provider|name|id|aliases|profiles
# Some rows encode extra keys in the first field with | separators before display.
# Format (fixed): key1|key2|...|display|provider|name|id|aliases|profiles
# We detect by counting: last 6 fields are fixed; earlier fields are keys.
lookup_marketplace() {
  local want="$1"
  local row keys_and_meta display provider name id aliases profiles
  local -a fields keys

  for row in "${MARKETPLACE_MODELS[@]}"; do
    IFS='|' read -r -a fields <<<"${row}"
    local n="${#fields[@]}"
    (( n >= 7 )) || continue

    profiles="${fields[$((n - 1))]}"
    aliases="${fields[$((n - 2))]}"
    id="${fields[$((n - 3))]}"
    name="${fields[$((n - 4))]}"
    provider="${fields[$((n - 5))]}"
    display="${fields[$((n - 6))]}"
    keys=("${fields[@]:0:$((n - 6))}")

    local key
    for key in "${keys[@]}" "$id"; do
      if [[ "${key}" == "${want}" ]]; then
        local model_name="${MODEL_NAME:-${name}}"
        local model_id="${MODEL_ID:-${id}}"
        local us_profile="" global_profile=""
        case "${profiles}" in
          us+global)
            us_profile="${US_PROFILE:-us.${model_id}}"
            global_profile="${GLOBAL_PROFILE:-global.${model_id}}"
            ;;
          us)
            us_profile="${US_PROFILE:-us.${model_id}}"
            ;;
          none) ;;
          *) die "invalid profiles mode '${profiles}' for ${display}" ;;
        esac
        upload_marketplace_manifest \
          "${display}" \
          "${provider}" \
          "${model_name}" \
          "${model_id}" \
          "${aliases}" \
          "${us_profile}" \
          "${global_profile}"
        return 0
      fi
    done
  done
  return 1
}

upload_minilm() {
  require_aws

  local local_dir="${ROOT}/models/MiniLM-L12-H384"
  local prefix="microsoft/MiniLM-L12-H384"
  local dest="${BUCKET}/${prefix}/"

  [[ -f "${local_dir}/config.json" ]] || die "missing ${local_dir}/config.json"
  [[ -f "${local_dir}/model.safetensors" ]] || die "missing ${local_dir}/model.safetensors"

  echo "Syncing ${local_dir} → ${dest}"
  aws s3 sync "${local_dir}" "${dest}" \
    --region "${REGION}" \
    --exclude ".cache/*"

  echo
  echo "Done. Weights at ${dest}"
  echo "The Lambda loads MiniLM in-process; S3 is only a package/CI fallback."
}

MODEL="${1:-}"
[[ -n "${MODEL}" ]] || { usage; exit 1; }
shift || true

case "${MODEL}" in
  -h|--help|help)
    usage
    ;;
  minilm-l12-h384|MiniLM-L12-H384|microsoft/MiniLM-L12-H384-uncased)
    upload_minilm
    ;;
  *)
    if ! lookup_marketplace "${MODEL}"; then
      die "unknown model '${MODEL}' (see --help)"
    fi
    ;;
esac
