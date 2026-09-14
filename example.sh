#!/usr/bin/env bash
# Smoke test. Uses profile bitaihang09132026 unless AWS_PROFILE is already set.
#
#   ./example.sh dev ministral-8b
#   ./example.sh prod
#   FUNCTION_URL='https://..../' INFERENCE_API_KEY='1234' ./example.sh llama4
#
# Omit the model name to hit every marketplace alias (sync + stream).
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
# shellcheck source=scripts/env-name.sh
source "${ROOT}/scripts/env-name.sh"
export AWS_PROFILE="${AWS_PROFILE:-bitaihang09132026}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export INFERENCE_API_KEY="${INFERENCE_API_KEY:-${API_KEY:-1234}}"

ENV="${1:-dev}"
case "${ENV}" in
  dev|prod) shift || true ;;
  *) ENV=dev ;;
esac

if [[ -z "${FUNCTION_URL:-}" ]]; then
  FUNCTION_NAME="$(env_function_name "${ENV}")"
  export FUNCTION_NAME
fi

exec ./scripts/smoke.sh "$@"
