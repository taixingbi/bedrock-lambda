#!/usr/bin/env bash
# Terraform for the stack.
#
#   ./scripts/tf.sh plan
#   ./scripts/tf.sh apply
#   ./scripts/tf.sh destroy
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=aws-env.sh
source "${ROOT}/scripts/aws-env.sh"
# shellcheck source=tf-common.sh
source "${ROOT}/scripts/tf-common.sh"

CMD="${1:-}"
case "${CMD}" in
  plan|apply|destroy) ;;
  *)
    echo "usage: $0 plan|apply|destroy" >&2
    exit 1
    ;;
esac
tf_prepare

# No key given: keep the one the deployed Lambda already uses.
if [[ "${CMD}" == "apply" && -z "${API_KEY}" ]]; then
  API_KEY="$(aws lambda get-function-configuration \
    --region "${REGION}" \
    --function-name "${FUNCTION_NAME}" \
    --query 'Environment.Variables.API_KEY' \
    --output text 2>/dev/null || true)"
  [[ "${API_KEY}" == "None" ]] && API_KEY=""
  if [[ -n "${API_KEY}" ]]; then
    echo "Reusing the API key already set on ${FUNCTION_NAME}."
  fi
fi
if [[ "${CMD}" == "apply" && -z "${API_KEY}" ]]; then
  echo "error: set API_KEY or INFERENCE_API_KEY (no existing ${FUNCTION_NAME} to reuse a key from)" >&2
  exit 1
fi
[[ -n "${API_KEY}" ]] || API_KEY="1234"

if [[ "${CMD}" == "destroy" ]]; then
  command -v python3 >/dev/null || { echo "error: python3 required" >&2; exit 1; }
  tf_ensure_zip dummy
elif [[ "${CMD}" == "apply" && "${SKIP_PACKAGE:-}" == "1" ]]; then
  [[ -f "${ZIP}" ]] || { echo "error: SKIP_PACKAGE=1 but missing ${ZIP}" >&2; exit 1; }
else
  tf_ensure_zip real
fi

tf_account_bucket
echo "${CMD} ${FUNCTION_NAME} in account ${ACCOUNT_ID}…"

if [[ "${CMD}" == "destroy" ]] && ! aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "No state bucket ${BUCKET}; nothing to destroy."
  exit 0
fi

tf_ensure_state_bucket "${BUCKET}"
tf_export_vars "${BUCKET}"
tf_init "${BUCKET}"

if [[ "${CMD}" == "destroy" ]]; then
  if ! terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q .; then
    echo "Empty state; nothing to destroy."
    exit 0
  fi
  terraform -chdir="${TF_DIR}" destroy -input=false -auto-approve
  echo
  echo "Destroy complete (${FUNCTION_NAME})."
  exit 0
fi

if [[ "${CMD}" == "plan" ]]; then
  terraform -chdir="${TF_DIR}" plan -input=false -no-color
  exit 0
fi

adopt_lambda_permission() {
  local addr="$1"
  local sid="$2"
  if terraform -chdir="${TF_DIR}" state show -no-color "${addr}" >/dev/null 2>&1; then
    return 0
  fi
  local policy
  policy="$(aws lambda get-policy --function-name "${FUNCTION_NAME}" --region "${REGION}" --query Policy --output text 2>/dev/null || true)"
  [[ -n "${policy}" && "${policy}" != "None" ]] || return 0
  if python3 -c '
import json, sys
policy = json.loads(sys.argv[1])
stmts = policy.get("Statement", [])
if isinstance(stmts, dict):
    stmts = [stmts]
sys.exit(0 if sys.argv[2] in {s.get("Sid") for s in stmts} else 1)
' "${policy}" "${sid}"; then
    echo "Importing existing Lambda permission ${sid}…"
    terraform -chdir="${TF_DIR}" import -input=false -no-color \
      "${addr}" "${FUNCTION_NAME}/${sid}"
  fi
}

adopt_lambda_permission module.inference.aws_lambda_permission.function_invoke FunctionURLAllowInvoke

terraform -chdir="${TF_DIR}" apply -input=false -auto-approve
echo
echo "Function URL:"
terraform -chdir="${TF_DIR}" output -raw function_url
echo
