#!/usr/bin/env bash
# Smoke-test a deployed environment.
#
#   ./smoke.sh dev ministral-8b
#   ./smoke.sh prod
#   FUNCTION_URL='https://..../' INFERENCE_API_KEY='1234' ./smoke.sh llama4
#
# Omit the model name to hit every marketplace alias (sync + stream).
# Looks up the Function URL with the AWS CLI unless FUNCTION_URL is set.
# Defaults to profile bitaihang09132026 only when that profile exists.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
# shellcheck source=scripts/env-name.sh
source "${ROOT}/scripts/env-name.sh"
# shellcheck source=scripts/aws-env.sh
source "${ROOT}/scripts/aws-env.sh"
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
