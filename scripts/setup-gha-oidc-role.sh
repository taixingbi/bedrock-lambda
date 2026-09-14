#!/usr/bin/env bash
# Create (or reuse) the root-account deploy role.
# Trust is GitHub OIDC only (sts:AssumeRoleWithWebIdentity).
# Run once with profile bitaihang09132026. Prints AWS_ROLE_ARN.
#
# Env:
#   ROLE_NAME   default github-actions-deploy
#   GITHUB_REPOSITORY  owner/name (detected from git remote if unset)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=aws-env.sh
source "${ROOT}/scripts/aws-env.sh"
ROLE_NAME="${ROLE_NAME:-github-actions-deploy}"
OIDC_URL="https://token.actions.githubusercontent.com"
OIDC_HOST="token.actions.githubusercontent.com"

die() { echo "error: $*" >&2; exit 1; }
command -v aws >/dev/null || die "aws CLI required"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REPO="${GITHUB_REPOSITORY:-}"
if [[ -z "${REPO}" ]]; then
  origin="$(git -C "${ROOT}" remote get-url origin 2>/dev/null || true)"
  REPO="$(sed -E 's#.*github.com[:/]([^/]+/[^/.]+)(\.git)?$#\1#' <<<"${origin}")"
fi
[[ "${REPO}" == */* ]] || die "set GITHUB_REPOSITORY=owner/name"

PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_HOST}"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${PROVIDER_ARN}" >/dev/null 2>&1; then
  echo "Creating OIDC provider ${OIDC_HOST}…"
  aws iam create-open-id-connect-provider \
    --url "${OIDC_URL}" \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null
fi

TRUST="$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "${PROVIDER_ARN}" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": { "${OIDC_HOST}:aud": "sts.amazonaws.com" },
        "StringLike": {
          "${OIDC_HOST}:sub": [
            "repo:${REPO}:*",
            "repo:${REPO%%/*}@*/${REPO#*/}@*:*"
          ]
        }
      }
    }
  ]
}
EOF
)"

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "Updating trust on ${ROLE_NAME}…"
  aws iam update-assume-role-policy --role-name "${ROLE_NAME}" --policy-document "${TRUST}"
else
  echo "Creating role ${ROLE_NAME}…"
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "${TRUST}" \
    --description "GitHub Actions OIDC deploy for ${REPO}" >/dev/null
fi

aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name deploy \
  --policy-document "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformDeploy",
      "Effect": "Allow",
      "Action": [
        "lambda:*",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:PassRole",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:TagRole",
        "iam:UntagRole",
        "s3:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)"

cat <<EOF

Done.

  Role   ${ROLE_ARN}
  Trust  repo:${REPO}:*

Deploy calls sts:AssumeRoleWithWebIdentity on this role. No AWS access-key secrets.

Optional variable (defaults to this role):

  AWS_ROLE_ARN=${ROLE_ARN}
EOF
