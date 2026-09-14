#!/usr/bin/env bash
# Function name comes from terraform/environments/<env>.tfvars.
env_function_name() {
  local env="$1"
  local file="${ROOT}/terraform/environments/${env}.tfvars"
  local name
  [[ -f "${file}" ]] || {
    echo "error: environment must be dev or prod" >&2
    return 1
  }
  name="$(awk -F'"' '/^function_name/{print $2; exit}' "${file}")"
  [[ -n "${name}" ]] || {
    echo "error: function_name missing in ${file}" >&2
    return 1
  }
  echo "${name}"
}

resolve_api_key() {
  local env="$1"
  local key="${API_KEY:-${INFERENCE_API_KEY:-}}"
  if [[ "${env}" == "prod" && -n "${INFERENCE_API_KEY_PROD:-}" ]]; then
    key="${INFERENCE_API_KEY_PROD}"
  elif [[ "${env}" == "dev" && -n "${INFERENCE_API_KEY_DEV:-}" ]]; then
    key="${INFERENCE_API_KEY_DEV}"
  fi
  printf '%s' "${key}"
}
