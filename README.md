# Bedrock MVP Inference API

Python Lambda with a Function URL that sends prompts to Amazon Bedrock via the boto3 **Converse** API.

## Prerequisites

1. Root AWS account (profile `bitaihang09132026`) with permission to create Lambda, IAM roles, and call Bedrock. Scripts default to that profile unless `AWS_ACCESS_KEY_ID` or `AWS_PROFILE` is already set.
2. [Model access enabled](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html) for marketplace models (default: `amazon.nova-lite-v1:0`)
3. [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.5) and Python 3.12 for local package/deploy
4. GitHub Actions assumes a deploy role with `sts:AssumeRoleWithWebIdentity`. From the account that owns the role, run `./scripts/setup-gha-oidc-role.sh` once, then add:

| Name | Where | Purpose |
| --- | --- | --- |
| `INFERENCE_API_KEY` | Secret | Shared secret clients must send as `x-api-key` |

Optional overrides when DEV and PROD are different accounts: variables `AWS_ROLE_ARN_DEV` / `AWS_ROLE_ARN_PROD`, secrets `INFERENCE_API_KEY_DEV` / `INFERENCE_API_KEY_PROD`. Until those are set, both environments use `AWS_ROLE_ARN` (default `arn:aws:iam::103714492562:role/github-actions-deploy`) and `INFERENCE_API_KEY`. State keys stay separate either way.

Optional repository variables:

| Variable | Purpose |
| --- | --- |
| `AWS_REGION` | Region for deploy and Bedrock (defaults to `us-east-1`) |
| `MODEL_ID` | Default Bedrock model ID when the request omits `model` (defaults to `amazon.nova-lite-v1:0`) |
| `MODEL_MAP` | Optional JSON object of request alias → Bedrock ID/ARN (merges with built-in aliases) |

The Lambda runs in the root account only (no member tenants). It talks to Bedrock with its **execution role**, not with the GitHub deploy role. Bedrock is managed inference — you do not choose a GPU.

## Models

The request `model` field selects which Bedrock backend to call. Built-in aliases:

| Request `model` | Bedrock ID | API |
| --- | --- | --- |
| `nova-pro` / `amazon.nova-pro-v1:0` | `amazon.nova-pro-v1:0` | Converse |
| `us.amazon.nova-pro-v1:0` | US geo inference profile | Converse |
| `nova-lite` / `amazon.nova-lite-v1:0` | `amazon.nova-lite-v1:0` | Converse |
| `nova-micro` / `amazon.nova-micro-v1:0` | `amazon.nova-micro-v1:0` | Converse |
| `llama` / `llama3.3` / `llama-3.3-70b` | `us.meta.llama3-3-70b-instruct-v1:0` | Converse |
| `llama4` / `llama4-maverick` | `us.meta.llama4-maverick-17b-instruct-v1:0` | Converse |
| `llama4-scout` | `us.meta.llama4-scout-17b-instruct-v1:0` | Converse |
| `gpt-oss` / `gpt-oss-120b` | `openai.gpt-oss-120b-1:0` | Converse |
| `gpt-oss-20b` | `openai.gpt-oss-20b-1:0` | Converse |
| `gpt-oss-safeguard-20b` | `openai.gpt-oss-safeguard-20b` | Converse |
| `gpt-oss-safeguard` / `gpt-oss-safeguard-120b` | `openai.gpt-oss-safeguard-120b` | Converse |
| `deepseek` / `deepseek.v3.2` | `deepseek.v3.2` | Converse |
| `deepseek-r1` | `us.deepseek.r1-v1:0` | Converse |
| `qwen3-next-80b-a3b` / `qwen.qwen3-next-80b-a3b` | `qwen.qwen3-next-80b-a3b` | Converse |
| `ministral-3b` / `ministral-3-3b` | `mistral.ministral-3-3b-instruct` | Converse |
| `ministral-8b` / `ministral-3-8b` | `mistral.ministral-3-8b-instruct` | Converse |
| `ministral-14b` / `ministral-3-14b` | `mistral.ministral-3-14b-instruct` | Converse |
| `gemma-3-4b` / `gemma-3-4b-it` | `google.gemma-3-4b-it` | Converse |
| `gemma-3-12b` / `gemma-3-12b-it` | `google.gemma-3-12b-it` | Converse |
| `gemma-3-27b` / `gemma-3-27b-it` | `google.gemma-3-27b-it` | Converse |
| `qwen3-32b` / `Qwen/Qwen3-32B` | `qwen.qwen3-32b-v1:0` | Converse |
| `minilm-l12-h384` / `MiniLM-L12-H384` | in-process classifier | MiniLM |

Raw Bedrock IDs and imported-model ARNs are also accepted. Unknown names return `400`.

Recommended open models (us-east-1, Bedrock Runtime):

| Model | 参数量 | Alias | Bedrock ID | us-east-1 | Bedrock Runtime | 推荐度 |
| --- | --- | --- | --- | --- | --- | --- |
| Ministral 3 3B | 3B | `ministral-3b` | `mistral.ministral-3-3b-instruct` | ✅ | ✅ | ⭐⭐⭐⭐ |
| Gemma 3 4B IT | 4B | `gemma-3-4b` | `google.gemma-3-4b-it` | ✅ | ✅ | ⭐⭐⭐ |
| Ministral 3 8B | 8B | `ministral-8b` | `mistral.ministral-3-8b-instruct` | ✅ | ✅ | ⭐⭐⭐⭐⭐ |
| Gemma 3 12B IT | 12B | `gemma-3-12b` | `google.gemma-3-12b-it` | ✅ | ✅ | ⭐⭐⭐⭐ |
| Ministral 3 14B | 14B | `ministral-14b` | `mistral.ministral-3-14b-instruct` | ✅ | ✅ | ⭐⭐⭐⭐⭐ |
| Llama 4 Maverick | 17B active (400B MoE) | `llama4` / `llama4-maverick` | `us.meta.llama4-maverick-17b-instruct-v1:0` | ✅ | ✅ | ⭐⭐⭐⭐ |
| Gemma 3 27B | 27B | `gemma-3-27b` | `google.gemma-3-27b-it` | ✅ | ✅ | ⭐⭐⭐ |
| Qwen3 32B | 32B | `qwen3-32b` | `qwen.qwen3-32b-v1:0` | ✅ | ✅ | ⭐⭐⭐⭐⭐ |

Override or add aliases with the `MODEL_MAP` env / repo variable, e.g.:

```json
{"my-model":"amazon.nova-pro-v1:0"}
```

### Default (marketplace)

`amazon.nova-lite-v1:0` — enable access in the Bedrock console for `us-east-1`, then deploy (or set repo variable `MODEL_ID`).

### Amazon Nova Pro (marketplace)

Enable model access in the Bedrock console, then call:

```json
{"model": "nova-pro", "messages": [{"role": "user", "content": "Hello"}]}
```

Optional catalog manifest:

```bash
./scripts/upload-model-to-s3.sh nova-pro
# → s3://huggingface-bedrock-models-103714492562/amazon/nova-pro-v1/model-manifest.json
```

| Mode | Bedrock ID |
| --- | --- |
| In-region (`us-east-1`) | `amazon.nova-pro-v1:0` |
| US geo cross-region | `us.amazon.nova-pro-v1:0` |

### Meta Llama (marketplace)

Enable Meta model access in the Bedrock console. Friendly aliases default to the **US geo inference profile** (required for on-demand on many Llama IDs):

```json
{"model": "llama", "messages": [{"role": "user", "content": "Hello"}]}
```

| Alias | Bedrock ID |
| --- | --- |
| `llama` / `llama3.3` | `us.meta.llama3-3-70b-instruct-v1:0` |
| `llama4` / `llama4-maverick` | `us.meta.llama4-maverick-17b-instruct-v1:0` |
| `llama4-scout` | `us.meta.llama4-scout-17b-instruct-v1:0` |

```bash
./scripts/upload-model-to-s3.sh llama
# → s3://huggingface-bedrock-models-103714492562/meta/llama3-3-70b-instruct/model-manifest.json
./scripts/upload-model-to-s3.sh llama4
# → s3://huggingface-bedrock-models-103714492562/meta/llama4-maverick-17b-instruct/model-manifest.json
```

### MiniLM-L12-H384 (in-process classifier)

Local BERT classifier in [`models/MiniLM-L12-H384`](models/MiniLM-L12-H384) (`microsoft/MiniLM-L12-H384-uncased`, WildGuardMix binary head). Not a Bedrock marketplace FM. The Lambda runs it in-process; assistant `content` is JSON `{"label","score","probs","tokens"}` (`unharmful` / `harmful`).

```json
{"model": "minilm-l12-h384", "messages": [{"role": "user", "content": "Hello"}]}
```

```bash
./scripts/upload-model-to-s3.sh MiniLM-L12-H384
# → s3://huggingface-bedrock-models-103714492562/microsoft/MiniLM-L12-H384/  (optional CI fallback)
```

### OpenAI GPT-OSS (marketplace)

Bedrock-hosted OpenAI open-weight models (not ChatGPT API keys). Enable access, then:

```json
{"model": "gpt-oss", "messages": [{"role": "user", "content": "Hello"}]}
```

| Alias | Bedrock ID |
| --- | --- |
| `gpt-oss` / `gpt-oss-120b` | `openai.gpt-oss-120b-1:0` |
| `gpt-oss-20b` | `openai.gpt-oss-20b-1:0` |
| `gpt-oss-safeguard-20b` | `openai.gpt-oss-safeguard-20b` |
| `gpt-oss-safeguard` / `gpt-oss-safeguard-120b` | `openai.gpt-oss-safeguard-120b` |

Safeguard variants are dedicated safety / content-moderation models (not general chat). They emit internal reasoning before the final text — use `max_tokens` ≥ 256. Enable access in the Bedrock console, then:

```json
{"model": "gpt-oss-safeguard-20b", "messages": [{"role": "user", "content": "Hello"}]}
{"model": "gpt-oss-safeguard-120b", "messages": [{"role": "user", "content": "Hello"}]}
```

```bash
./scripts/upload-model-to-s3.sh gpt-oss
# → s3://huggingface-bedrock-models-103714492562/openai/gpt-oss-120b/model-manifest.json
./scripts/upload-model-to-s3.sh gpt-oss-safeguard-20b
./scripts/upload-model-to-s3.sh gpt-oss-safeguard-120b
```

### DeepSeek (marketplace)

Enable DeepSeek access, then:

```json
{"model": "deepseek", "messages": [{"role": "user", "content": "Hello"}]}
```

| Alias | Bedrock ID |
| --- | --- |
| `deepseek` / `deepseek-v3.2` | `deepseek.v3.2` |
| `deepseek-r1` | `us.deepseek.r1-v1:0` |

```bash
./scripts/upload-model-to-s3.sh deepseek
# → s3://huggingface-bedrock-models-103714492562/deepseek/deepseek-v3.2/model-manifest.json
```

### Qwen3 Next 80B A3B (marketplace)

Fully managed open-weight model on Bedrock (Converse). Enable access, then:

```json
{"model": "qwen3-next-80b-a3b", "messages": [{"role": "user", "content": "Hello"}]}
```

| Alias | Bedrock ID |
| --- | --- |
| `qwen3-next-80b-a3b` | `qwen.qwen3-next-80b-a3b` |
| `Qwen/Qwen3-Next-80B-A3B-Instruct` | `qwen.qwen3-next-80b-a3b` |

No geo inference profiles (in-region only).

```bash
./scripts/upload-model-to-s3.sh qwen3-next-80b-a3b
# → s3://huggingface-bedrock-models-103714492562/qwen/qwen3-next-80b-a3b/model-manifest.json
```

### Ministral 3 / Gemma 3 / Qwen3 32B (marketplace)

Fully managed open-weight models on Bedrock (Converse). Enable access in `us-east-1`, then call:

```json
{"model": "ministral-8b", "messages": [{"role": "user", "content": "Hello"}]}
{"model": "gemma-3-12b", "messages": [{"role": "user", "content": "Hello"}]}
{"model": "qwen3-32b", "messages": [{"role": "user", "content": "Hello"}]}
```

| Alias | Bedrock ID |
| --- | --- |
| `ministral-3b` | `mistral.ministral-3-3b-instruct` |
| `ministral-8b` | `mistral.ministral-3-8b-instruct` |
| `ministral-14b` | `mistral.ministral-3-14b-instruct` |
| `gemma-3-4b` | `google.gemma-3-4b-it` |
| `gemma-3-12b` | `google.gemma-3-12b-it` |
| `gemma-3-27b` | `google.gemma-3-27b-it` |
| `qwen3-32b` | `qwen.qwen3-32b-v1:0` |

No geo inference profiles (in-region only).

```bash
./scripts/upload-model-to-s3.sh ministral-3b
./scripts/upload-model-to-s3.sh ministral-8b
./scripts/upload-model-to-s3.sh ministral-14b
./scripts/upload-model-to-s3.sh gemma-3-4b
./scripts/upload-model-to-s3.sh gemma-3-12b
./scripts/upload-model-to-s3.sh gemma-3-27b
./scripts/upload-model-to-s3.sh qwen3-32b
```

Shared models bucket (`us-east-1`) holds optional marketplace manifests (no HF weights) under `amazon/`, `meta/`, `openai/`, `deepseek/`, `qwen/`, `mistral/`, `google/`.

The handler picks the Bedrock API per resolved model:

- Marketplace models (Nova, Llama, GPT-OSS, DeepSeek, Qwen3, Ministral, Gemma, …) → **Converse**
- `minilm-l12-h384` / `MiniLM-L12-H384` → **in-process** MiniLM classifier
- Raw imported-model ARNs (`:imported-model/…`) → **InvokeModel**

## API

### OpenAI-compatible (preferred)

`POST` `/v1/chat/completions`

```json
{
  "model": "ministral-8b",
  "messages": [
    {"role": "system", "content": "optional system prompt"},
    {"role": "user", "content": "Hello"}
  ],
  "max_tokens": 512,
  "temperature": 0,
  "top_p": 1.0
}
```

Headers (either works):

- `Authorization: Bearer <INFERENCE_API_KEY>`
- `x-api-key: <INFERENCE_API_KEY>`

Success (OpenAI chat.completion shape):

```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 0,
  "model": "ministral-8b",
  "choices": [
    {
      "index": 0,
      "message": {"role": "assistant", "content": "..."},
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 0,
    "completion_tokens": 0,
    "total_tokens": 0
  }
}
```

The `model` field selects the Bedrock backend (see [Models](#models)); the same name is echoed in the response.

Set `"stream": true` to receive OpenAI SSE (`text/event-stream`) chunks (`chat.completion.chunk` then `data: [DONE]`). Streaming uses Lambda Function URL `RESPONSE_STREAM` plus Bedrock `InvokeModelWithResponseStream` / `ConverseStream`.

## Deploy

Environments are directories and state files, not branches. `feature/*` → pull request → `main`. The same commit is what DEV runs, and what PROD runs after approval.

```
feature/* → PR
              ├── terraform fmt / validate / plan (dev and prod)
              └── compile the app
            merge
              ↓
            main
              ├── infra apply DEV
              ├── app publish DEV
              ├── DEV validation
              ├── GitHub Environment `production` approval
              ├── infra apply PROD
              └── app publish PROD
```

PROD does not start until you comment `approved` on the issue opened by the `approve-prod` job. Comment `denied` to stop. The job waits up to 6 hours.

| Environment | Function | State key |
| --- | --- | --- |
| dev | `bedrock-inference-dev` | `environments/dev/terraform.tfstate` |
| prod | `bedrock-inference-prod` | `environments/prod/terraform.tfstate` |

Renaming a function replaces that Lambda and its Function URL. Point `AWS_ROLE_ARN_DEV` and `AWS_ROLE_ARN_PROD` at different accounts when you have them; do not add a `dev` or `prod` branch.

Local commands use profile `bitaihang09132026`. After deploy, get a Function URL:

```bash
aws lambda get-function-url-config \
  --profile bitaihang09132026 \
  --region us-east-1 \
  --function-name bedrock-inference-prod
  --query FunctionUrl \
  --output text
```

Or in the AWS Console: Lambda → `bedrock-inference-prod` → **Configuration** → **Function URL**.

### Manual deploy

```bash
export API_KEY='your-shared-secret'
./scripts/tf.sh apply dev
./scripts/app-deploy.sh dev
./scripts/tf.sh plan prod
```

Tear down one environment (the other state's resources stay):

```bash
./scripts/tf.sh destroy dev
```

## Call the API

Example (`ministral-8b`):

```bash
FUNCTION_URL=$(aws lambda get-function-url-config \
  --profile bitaihang09132026 \
  --region us-east-1 \
  --function-name bedrock-inference-prod
  --query FunctionUrl \
  --output text)
INFERENCE_API_KEY='1234'

curl -sS -N -X POST "${FUNCTION_URL}v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${INFERENCE_API_KEY}" \
  -d '{
    "model": "ministral-8b",
    "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
    "max_tokens": 64,
    "temperature": 0,
    "stream": true
  }'
```

See [`smoke.sh`](smoke.sh) (`./smoke.sh dev ministral-8b`, or `./smoke.sh prod`) for a sync+stream smoke test against that environment's Function URL.

Amazon Nova Pro (marketplace):

```bash
curl -sS -X POST "${FUNCTION_URL}v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${INFERENCE_API_KEY}" \
  -d '{
    "model": "nova-pro",
    "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
    "max_tokens": 64,
    "temperature": 0
  }' | jq '{model, answer: .choices[0].message.content, usage}'
```

Meta Llama 3.3 (marketplace):

```bash
curl -sS -X POST "${FUNCTION_URL}v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${INFERENCE_API_KEY}" \
  -d '{
    "model": "llama",
    "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
    "max_tokens": 64,
    "temperature": 0
  }' | jq '{model, answer: .choices[0].message.content, usage}'
```

Meta Llama 4 Maverick (marketplace):

```bash
curl -sS -X POST "${FUNCTION_URL}v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${INFERENCE_API_KEY}" \
  -d '{
    "model": "llama4",
    "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
    "max_tokens": 64,
    "temperature": 0
  }' | jq '{model, answer: .choices[0].message.content, usage}'
```

OpenAI GPT-OSS (marketplace):

```bash
curl -sS -X POST "${FUNCTION_URL}v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${INFERENCE_API_KEY}" \
  -d '{
    "model": "gpt-oss",
    "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
    "max_tokens": 64,
    "temperature": 0
  }' | jq '{model, answer: .choices[0].message.content, usage}'
```

DeepSeek V3.2 (marketplace):

```bash
curl -sS -X POST "${FUNCTION_URL}v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${INFERENCE_API_KEY}" \
  -d '{
    "model": "deepseek",
    "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
    "max_tokens": 64,
    "temperature": 0
  }' | jq '{model, answer: .choices[0].message.content, usage}'
```

Qwen3 Next 80B A3B (marketplace):

```bash
curl -sS -X POST "${FUNCTION_URL}v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${INFERENCE_API_KEY}" \
  -d '{
    "model": "qwen3-next-80b-a3b",
    "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
    "max_tokens": 64,
    "temperature": 0
  }' | jq '{model, answer: .choices[0].message.content, usage}'
```

Ministral 3 8B (marketplace):

```bash
curl -sS -X POST "${FUNCTION_URL}v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${INFERENCE_API_KEY}" \
  -d '{
    "model": "ministral-8b",
    "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
    "max_tokens": 64,
    "temperature": 0
  }' | jq '{model, answer: .choices[0].message.content, usage}'
```

Gemma 3 12B IT (marketplace):

```bash
curl -sS -X POST "${FUNCTION_URL}v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${INFERENCE_API_KEY}" \
  -d '{
    "model": "gemma-3-12b",
    "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
    "max_tokens": 64,
    "temperature": 0
  }' | jq '{model, answer: .choices[0].message.content, usage}'
```

Qwen3 32B (marketplace):

```bash
curl -sS -X POST "${FUNCTION_URL}v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${INFERENCE_API_KEY}" \
  -d '{
    "model": "qwen3-32b",
    "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
    "max_tokens": 64,
    "temperature": 0
  }' | jq '{model, answer: .choices[0].message.content, usage}'
```

## Local invoke

Run the FastAPI app locally (uses your AWS credentials for Bedrock):

```bash
export API_KEY=local-dev-key
export MODEL_ID=amazon.nova-lite-v1:0
pip install -r src/requirements.txt
uvicorn app:app --app-dir src --host 127.0.0.1 --port 8080
```

Then:

```bash
curl -sS -N -X POST "http://127.0.0.1:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer local-dev-key" \
  -d '{
    "model": "ministral-8b",
    "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
    "max_tokens": 64,
    "temperature": 0,
    "stream": true
  }'
```# bedrock-lambda
