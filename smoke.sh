#!/usr/bin/env bash
# Smoke-test the deployed Function URL.
#
#   ./smoke.sh ministral-8b
#   ./smoke.sh
#   FUNCTION_URL='https://..../' INFERENCE_API_KEY='1234' ./smoke.sh llama4
#
# Omit the model name to hit every marketplace alias (sync + stream).
# Looks up the Function URL with the AWS CLI unless FUNCTION_URL is set.
# Defaults to profile bitaihang09132026 only when that profile exists.
set -euo pipefail

cd "$(dirname "$0")"
exec ./scripts/smoke.sh "$@"
