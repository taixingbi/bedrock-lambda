#!/usr/bin/env bash
# Terraform for one environment. State is selected by the environment name.
#
#   ./scripts/tf.sh plan dev
#   ./scripts/tf.sh apply prod
#   ./scripts/tf.sh destroy dev
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
    echo "usage: $0 plan|apply|destroy dev|prod" >&2
    exit 1
    ;;
esac
tf_prepare "${2:-}"

if [[ "${CMD}" == "apply" && -z "${API_KEY}" ]]; then
  echo "error: API_KEY or INFERENCE_API_KEY is required" >&2
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
echo "${CMD} ${ENV} (${FUNCTION_NAME}) in account ${ACCOUNT_ID}…"

if [[ "${CMD}" == "destroy" ]] && ! aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "No state bucket ${BUCKET}; nothing to destroy."
  exit 0
fi

tf_ensure_state_bucket "${BUCKET}"
tf_export_vars "${BUCKET}"
if [[ "${CMD}" != "destroy" ]]; then
  tf_seed_prod_state "${BUCKET}"
fi
tf_init "${BUCKET}"

if [[ "${CMD}" == "destroy" ]]; then
  if ! terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q .; then
    echo "Empty state for ${ENV}; nothing to destroy."
    exit 0
  fi
  terraform -chdir="${TF_DIR}" destroy -input=false -auto-approve -var-file="${VAR_FILE}"
  echo
  echo "Destroy complete (${ENV} / ${FUNCTION_NAME})."
  exit 0
fi

if [[ "${CMD}" == "plan" ]]; then
  terraform -chdir="${TF_DIR}" plan -input=false -no-color -var-file="${VAR_FILE}"
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
    terraform -chdir="${TF_DIR}" import -input=false -no-color -var-file="${VAR_FILE}" \
      "${addr}" "${FUNCTION_NAME}/${sid}"
  fi
}

adopt_lambda_permission module.inference.aws_lambda_permission.function_invoke FunctionURLAllowInvoke

terraform -chdir="${TF_DIR}" apply -input=false -auto-approve -var-file="${VAR_FILE}"
echo
echo "Function URL (${ENV}):"
terraform -chdir="${TF_DIR}" output -raw function_url
echo
