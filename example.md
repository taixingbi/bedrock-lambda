# Smoke test

The runner is [`scripts/smoke.sh`](scripts/smoke.sh), not this file. It uses AWS profile `bitaihang09132026` (the root account).

```bash
# Root account (profile bitaihang09132026):
./scripts/smoke.sh ministral-8b

# Explicit URL (no aws needed):
FUNCTION_URL='https://..../' INFERENCE_API_KEY='1234' ./scripts/smoke.sh llama4
```

Omit the model name to hit every marketplace alias (sync + stream). Curl uses the API key only.
