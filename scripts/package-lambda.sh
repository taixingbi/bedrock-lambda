#!/usr/bin/env bash
# Package src/ plus pip dependencies into a Lambda zip (replaces sam build).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-${ROOT}/terraform/.build/lambda.zip}"
STAGE="$(mktemp -d)"
cleanup() { rm -rf "${STAGE}"; }
trap cleanup EXIT

MINILM_SRC="${ROOT}/models/MiniLM-L12-H384"
# MiniLM is optional. Without weights the zip still serves every Bedrock model;
# only minilm-l12-h384 requests fail ("weights not packaged").
WITH_MINILM=1
if ! "${ROOT}/scripts/fetch-minilm-weights.sh"; then
  WITH_MINILM=0
elif [[ ! -f "${MINILM_SRC}/tokenizer.json" || ! -f "${MINILM_SRC}/config.json" ]]; then
  echo "warning: missing MiniLM tokenizer/config in ${MINILM_SRC}" >&2
  WITH_MINILM=0
fi
if [[ "${WITH_MINILM}" == "0" ]]; then
  echo "warning: packaging without MiniLM weights; minilm-l12-h384 will be unavailable" >&2
fi

cp "${ROOT}/src/app.py" "${ROOT}/src/minilm.py" "${ROOT}/src/requirements.txt" "${ROOT}/src/run.sh" \
  "${ROOT}/models/models.json" "${STAGE}/"
chmod +x "${STAGE}/run.sh"
# Lambda is python3.12 x86_64. A host pip install on macOS ARM pulls the wrong
# pydantic-core wheel and the function exits with Runtime.ExitError.
python3 -m pip install -q \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --python-version 3.12 \
  --only-binary=:all: \
  -r "${ROOT}/src/requirements.txt" \
  -t "${STAGE}"
find "${STAGE}" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true

if [[ "${WITH_MINILM}" == "1" ]]; then
  MINILM_DEST="${STAGE}/MiniLM-L12-H384"
  mkdir -p "${MINILM_DEST}"
  cp "${MINILM_SRC}/tokenizer.json" "${MINILM_SRC}/config.json" "${MINILM_DEST}/"
  # STAGE numpy is a manylinux wheel and cannot import on macOS. Prefer it on
  # Linux CI; fall back to a host venv for the float16 conversion.
  PACK_PY=""
  if PYTHONPATH="${STAGE}" python3 -c "import numpy" >/dev/null 2>&1; then
    PACK_PY=(env PYTHONPATH="${STAGE}${PYTHONPATH:+:${PYTHONPATH}}" python3)
  elif [[ -x "${ROOT}/.venv-minilm/bin/python" ]] \
    && "${ROOT}/.venv-minilm/bin/python" -c "import numpy" >/dev/null 2>&1; then
    PACK_PY=("${ROOT}/.venv-minilm/bin/python")
  else
    HOST_VENV="$(mktemp -d)"
    python3 -m venv "${HOST_VENV}"
    "${HOST_VENV}/bin/pip" install -q numpy
    PACK_PY=("${HOST_VENV}/bin/python")
  fi
  "${PACK_PY[@]}" "${ROOT}/scripts/pack-minilm.py" "${MINILM_SRC}" "${MINILM_DEST}/weights.npz"
fi


python3 - "${STAGE}" "${DEST}" <<'PY'
import pathlib
import sys
import zipfile

stage = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
dest.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for path in sorted(stage.rglob("*")):
        if path.is_file():
            zf.write(path, path.relative_to(stage).as_posix())
print(f"Wrote {dest} ({dest.stat().st_size} bytes)")
PY
