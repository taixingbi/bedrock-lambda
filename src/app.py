import hmac
import json
import os
import time
import uuid
from collections.abc import Iterator
from typing import Any, NamedTuple

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, Header, Request, Response
from fastapi.responses import JSONResponse, StreamingResponse

bedrock = boto3.client("bedrock-runtime")

DEFAULT_MODEL_ID = os.environ.get("MODEL_ID", "amazon.nova-lite-v1:0")
API_KEY = os.environ.get("API_KEY", "")

# In-process MiniLM-L12-H384 classifier (not a Bedrock FM).
MINILM_ID = "minilm-l12-h384"

_RAW_MODEL_PREFIXES = (
    "arn:aws:bedrock:",
    "anthropic.",
    "amazon.",
    "meta.",
    "openai.",
    "deepseek.",
    "qwen.",
    "mistral.",
    "google.",
    "us.",
    "eu.",
    "au.",
    "global.",
)

_STREAM_ERROR_KEYS = (
    "internalServerException",
    "modelStreamErrorException",
    "validationException",
    "throttlingException",
    "modelTimeoutException",
    "serviceUnavailableException",
)


def _alias_entries(*names: str, to: str) -> dict[str, str]:
    return {name: to for name in names}


# Friendly request names → Bedrock model ID / imported-model ARN.
_BUILTIN_MODEL_ALIASES: dict[str, str] = {
    **_alias_entries("nova-lite", "amazon.nova-lite-v1:0", to="amazon.nova-lite-v1:0"),
    **_alias_entries("nova-micro", "amazon.nova-micro-v1:0", to="amazon.nova-micro-v1:0"),
    **_alias_entries("us.amazon.nova-micro-v1:0", to="us.amazon.nova-micro-v1:0"),
    **_alias_entries("nova-pro", "amazon.nova-pro-v1:0", to="amazon.nova-pro-v1:0"),
    **_alias_entries("us.amazon.nova-pro-v1:0", to="us.amazon.nova-pro-v1:0"),
    # Meta Llama — default to US geo inference profiles (on-demand).
    **_alias_entries(
        "llama",
        "llama3.3",
        "llama-3.3-70b",
        "us.meta.llama3-3-70b-instruct-v1:0",
        to="us.meta.llama3-3-70b-instruct-v1:0",
    ),
    **_alias_entries(
        "meta.llama3-3-70b-instruct-v1:0",
        to="meta.llama3-3-70b-instruct-v1:0",
    ),
    **_alias_entries(
        "llama4",
        "llama4-maverick",
        "llama-4-maverick",
        "us.meta.llama4-maverick-17b-instruct-v1:0",
        to="us.meta.llama4-maverick-17b-instruct-v1:0",
    ),
    **_alias_entries(
        "meta.llama4-maverick-17b-instruct-v1:0",
        to="meta.llama4-maverick-17b-instruct-v1:0",
    ),
    **_alias_entries(
        "llama4-scout",
        "llama-4-scout",
        "us.meta.llama4-scout-17b-instruct-v1:0",
        to="us.meta.llama4-scout-17b-instruct-v1:0",
    ),
    **_alias_entries(
        "meta.llama4-scout-17b-instruct-v1:0",
        to="meta.llama4-scout-17b-instruct-v1:0",
    ),
    # OpenAI GPT-OSS (Bedrock-hosted open weights).
    **_alias_entries(
        "gpt-oss",
        "gpt-oss-120b",
        "openai.gpt-oss-120b-1:0",
        to="openai.gpt-oss-120b-1:0",
    ),
    **_alias_entries("gpt-oss-20b", "openai.gpt-oss-20b-1:0", to="openai.gpt-oss-20b-1:0"),
    # OpenAI GPT-OSS Safeguard (safety / content moderation).
    **_alias_entries(
        "gpt-oss-safeguard-20b",
        "openai.gpt-oss-safeguard-20b",
        to="openai.gpt-oss-safeguard-20b",
    ),
    **_alias_entries(
        "gpt-oss-safeguard",
        "gpt-oss-safeguard-120b",
        "openai.gpt-oss-safeguard-120b",
        to="openai.gpt-oss-safeguard-120b",
    ),
    # DeepSeek (marketplace).
    **_alias_entries("deepseek", "deepseek-v3.2", "deepseek.v3.2", to="deepseek.v3.2"),
    **_alias_entries(
        "deepseek-r1",
        "us.deepseek.r1-v1:0",
        to="us.deepseek.r1-v1:0",
    ),
    **_alias_entries("deepseek.r1-v1:0", to="deepseek.r1-v1:0"),
    # Qwen3 Next 80B A3B (marketplace).
    **_alias_entries(
        "qwen3-next-80b-a3b",
        "qwen.qwen3-next-80b-a3b",
        "Qwen/Qwen3-Next-80B-A3B-Instruct",
        to="qwen.qwen3-next-80b-a3b",
    ),
    # Ministral 3 (marketplace).
    **_alias_entries(
        "ministral-3b",
        "ministral-3-3b",
        "mistral.ministral-3-3b-instruct",
        to="mistral.ministral-3-3b-instruct",
    ),
    **_alias_entries(
        "ministral-8b",
        "ministral-3-8b",
        "mistral.ministral-3-8b-instruct",
        to="mistral.ministral-3-8b-instruct",
    ),
    **_alias_entries(
        "ministral-14b",
        "ministral-3-14b",
        "mistral.ministral-3-14b-instruct",
        to="mistral.ministral-3-14b-instruct",
    ),
    # Gemma 3 IT (marketplace).
    **_alias_entries(
        "gemma-3-4b",
        "gemma-3-4b-it",
        "google.gemma-3-4b-it",
        to="google.gemma-3-4b-it",
    ),
    **_alias_entries(
        "gemma-3-12b",
        "gemma-3-12b-it",
        "google.gemma-3-12b-it",
        to="google.gemma-3-12b-it",
    ),
    **_alias_entries(
        "gemma-3-27b",
        "gemma-3-27b-it",
        "google.gemma-3-27b-it",
        to="google.gemma-3-27b-it",
    ),
    # Qwen3 32B dense (marketplace).
    **_alias_entries(
        "qwen3-32b",
        "qwen.qwen3-32b-v1:0",
        "Qwen/Qwen3-32B",
        to="qwen.qwen3-32b-v1:0",
    ),
    # MiniLM-L12-H384 (in-process BERT classifier).
    **_alias_entries(
        "minilm-l12-h384",
        "MiniLM-L12-H384",
        "microsoft/MiniLM-L12-H384-uncased",
        to=MINILM_ID,
    ),
}


def _is_imported_model(model_id: str) -> bool:
    return ":imported-model/" in model_id


def _is_minilm(model_id: str) -> bool:
    return model_id == MINILM_ID


def _load_model_map() -> dict[str, str]:
    mapping = dict(_BUILTIN_MODEL_ALIASES)
    mapping[DEFAULT_MODEL_ID] = DEFAULT_MODEL_ID

    raw = os.environ.get("MODEL_MAP", "").strip()
    if raw:
        try:
            extra = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"MODEL_MAP must be valid JSON: {exc}") from exc
        if not isinstance(extra, dict):
            raise RuntimeError("MODEL_MAP must be a JSON object of alias → bedrock id")
        for key, value in extra.items():
            if not isinstance(key, str) or not isinstance(value, str):
                raise RuntimeError("MODEL_MAP keys and values must be strings")
            mapping[key] = value
    return mapping


MODEL_MAP = _load_model_map()
_KNOWN_MODEL_NAMES = ", ".join(
    sorted(
        name
        for name in MODEL_MAP
        if not name.startswith(_RAW_MODEL_PREFIXES) and "/" not in name
    )
)

app = FastAPI(title="mvp-bedrock")


class _InferRequest(NamedTuple):
    messages: list[dict[str, str]]
    max_tokens: int
    temperature: float | None
    top_p: float | None
    response_model: str
    bedrock_model_id: str
    stream: bool


def _resolve_model(request_model: Any) -> tuple[str, str]:
    """Return (response_model_name, bedrock_model_id)."""
    if request_model is None or request_model == "":
        return DEFAULT_MODEL_ID, DEFAULT_MODEL_ID
    if not isinstance(request_model, str):
        raise ValueError("model must be a string")

    name = request_model.strip()
    if name in MODEL_MAP:
        bedrock_model_id = MODEL_MAP[name]
        return name, bedrock_model_id

    if name.startswith(_RAW_MODEL_PREFIXES):
        return name, name

    raise ValueError(f"unknown model '{name}'; known: {_KNOWN_MODEL_NAMES}")


def _secret_equal(given: str, expected: str) -> bool:
    given_b = given.encode("utf-8")
    expected_b = expected.encode("utf-8")
    if len(given_b) != len(expected_b):
        hmac.compare_digest(expected_b, expected_b)
        return False
    return hmac.compare_digest(given_b, expected_b)


def _authorized(x_api_key: str | None, authorization: str | None) -> bool:
    if not API_KEY:
        return False
    if x_api_key is not None and _secret_equal(x_api_key, API_KEY):
        return True
    if authorization and authorization.lower().startswith("bearer "):
        return _secret_equal(authorization[7:].strip(), API_KEY)
    return False


def _unauthorized() -> JSONResponse:
    return JSONResponse(status_code=401, content={"error": "unauthorized"})


def _reasoning_text(block: dict[str, Any]) -> str:
    reasoning = block.get("reasoningContent") or {}
    if not isinstance(reasoning, dict):
        return ""
    text = reasoning.get("text")
    if isinstance(text, str) and text:
        return text
    nested = reasoning.get("reasoningText") or {}
    if isinstance(nested, dict):
        nested_text = nested.get("text")
        if isinstance(nested_text, str) and nested_text:
            return nested_text
    return ""


def _converse_delta_text(delta: dict[str, Any]) -> str:
    text = delta.get("text")
    if isinstance(text, str) and text:
        return text
    return _reasoning_text(delta)


def _extract_converse_text(converse_response: dict[str, Any]) -> str:
    parts: list[str] = []
    reasoning_parts: list[str] = []
    message = converse_response.get("output", {}).get("message", {})
    for block in message.get("content", []):
        text = block.get("text")
        if text:
            parts.append(text)
            continue
        # GPT-OSS / Safeguard may return only reasoningContent when max_tokens
        # is spent before the final text block.
        reasoning = _reasoning_text(block)
        if reasoning:
            reasoning_parts.append(reasoning)
    return "".join(parts) or "".join(reasoning_parts)


def _extract_invoke_text(invoke_body: dict[str, Any]) -> str:
    choices = invoke_body.get("choices")
    if isinstance(choices, list) and choices:
        message = choices[0].get("message") or {}
        content = message.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            parts: list[str] = []
            for block in content:
                if isinstance(block, dict) and isinstance(block.get("text"), str):
                    parts.append(block["text"])
                elif isinstance(block, str):
                    parts.append(block)
            return "".join(parts)

    generation = invoke_body.get("generation")
    if isinstance(generation, str):
        return generation

    outputs = invoke_body.get("outputs")
    if isinstance(outputs, list) and outputs:
        text = outputs[0].get("text")
        if isinstance(text, str):
            return text

    return ""


def _parse_sampling(payload: dict[str, Any]) -> tuple[int, float | None, float | None]:
    max_tokens = payload.get("max_tokens", 512)
    if not isinstance(max_tokens, int) or max_tokens < 1 or max_tokens > 4096:
        raise ValueError("max_tokens must be an integer between 1 and 4096")

    temperature = payload.get("temperature")
    if temperature is not None and (
        not isinstance(temperature, (int, float)) or temperature < 0 or temperature > 2
    ):
        raise ValueError("temperature must be a number between 0 and 2")

    top_p = payload.get("top_p")
    if top_p is not None and (not isinstance(top_p, (int, float)) or top_p <= 0 or top_p > 1):
        raise ValueError("top_p must be a number between 0 and 1")

    return (
        max_tokens,
        float(temperature) if temperature is not None else None,
        float(top_p) if top_p is not None else None,
    )


def _normalize_messages(payload: dict[str, Any]) -> list[dict[str, str]]:
    messages = payload.get("messages")
    if isinstance(messages, list) and messages:
        normalized: list[dict[str, str]] = []
        for item in messages:
            if not isinstance(item, dict):
                raise ValueError("each message must be an object")
            role = item.get("role")
            content = item.get("content")
            if role not in ("system", "user", "assistant"):
                raise ValueError("message.role must be system, user, or assistant")
            if not isinstance(content, str):
                raise ValueError("message.content must be a string")
            normalized.append({"role": role, "content": content})
        if not any(m["role"] == "user" for m in normalized):
            raise ValueError("at least one user message is required")
        return normalized

    prompt = payload.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        raise ValueError("messages or prompt is required")

    normalized: list[dict[str, str]] = []
    system = payload.get("system")
    if isinstance(system, str) and system.strip():
        normalized.append({"role": "system", "content": system})
    normalized.append({"role": "user", "content": prompt})
    return normalized


def _split_system(messages: list[dict[str, str]]) -> tuple[str | None, list[dict[str, str]]]:
    system_parts = [m["content"] for m in messages if m["role"] == "system"]
    rest = [m for m in messages if m["role"] != "system"]
    system = "\n\n".join(system_parts) if system_parts else None
    return system, rest


def _invoke_body(
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float | None,
    top_p: float | None,
    *,
    stream: bool,
) -> dict[str, Any]:
    body: dict[str, Any] = {
        "messages": messages,
        "max_tokens": max_tokens,
        "stream": stream,
    }
    if temperature is not None:
        body["temperature"] = temperature
    if top_p is not None:
        body["top_p"] = top_p
    return body


def _first_int(usage: dict[str, Any], keys: tuple[str, ...]) -> int:
    for key in keys:
        value = usage.get(key)
        if value is not None:
            return int(value)
    return 0


def _usage_from_keys(
    usage: dict[str, Any],
    prompt_keys: tuple[str, ...],
    completion_keys: tuple[str, ...],
) -> dict[str, int]:
    return {
        "prompt_tokens": _first_int(usage, prompt_keys),
        "completion_tokens": _first_int(usage, completion_keys),
    }


def _converse_args(
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float | None,
    top_p: float | None,
    bedrock_model_id: str,
) -> dict[str, Any]:
    system, rest = _split_system(messages)
    inference_config: dict[str, Any] = {"maxTokens": max_tokens}
    if temperature is not None:
        inference_config["temperature"] = temperature
    if top_p is not None:
        inference_config["topP"] = top_p

    args: dict[str, Any] = {
        "modelId": bedrock_model_id,
        "messages": [
            {"role": m["role"], "content": [{"text": m["content"]}]} for m in rest
        ],
        "inferenceConfig": inference_config,
    }
    if system:
        args["system"] = [{"text": system}]
    return args


def _infer_converse(
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float | None,
    top_p: float | None,
    bedrock_model_id: str,
) -> dict[str, Any]:
    result = bedrock.converse(
        **_converse_args(messages, max_tokens, temperature, top_p, bedrock_model_id)
    )
    return {
        "text": _extract_converse_text(result),
        "usage": _usage_from_keys(
            result.get("usage") or {},
            ("inputTokens",),
            ("outputTokens",),
        ),
    }


def _infer_invoke_model(
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float | None,
    top_p: float | None,
    bedrock_model_id: str,
) -> dict[str, Any]:
    raw = bedrock.invoke_model(
        modelId=bedrock_model_id,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(
            _invoke_body(messages, max_tokens, temperature, top_p, stream=False)
        ),
    )
    response_body = json.loads(raw["body"].read())
    return {
        "text": _extract_invoke_text(response_body),
        "usage": _usage_from_keys(
            response_body.get("usage") or {},
            ("prompt_tokens", "inputTokens", "input_tokens"),
            ("completion_tokens", "outputTokens", "output_tokens"),
        ),
    }


def _openai_completion(model: str, text: str, usage: dict[str, int]) -> dict[str, Any]:
    prompt_tokens = int(usage.get("prompt_tokens", 0) or 0)
    completion_tokens = int(usage.get("completion_tokens", 0) or 0)
    return {
        "id": f"chatcmpl-{uuid.uuid4().hex[:24]}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": text},
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": prompt_tokens + completion_tokens,
        },
    }


def _legacy_infer_response(model: str, text: str, usage: dict[str, int]) -> dict[str, Any]:
    return {
        "text": text,
        "model": model,
        "usage": {
            "input_tokens": int(usage.get("prompt_tokens", 0) or 0),
            "output_tokens": int(usage.get("completion_tokens", 0) or 0),
        },
    }


def _sse(data: str) -> str:
    return f"data: {data}\n\n"


def _openai_chunk(
    *,
    completion_id: str,
    created: int,
    model: str,
    delta: dict[str, Any],
    finish_reason: str | None = None,
) -> dict[str, Any]:
    return {
        "id": completion_id,
        "object": "chat.completion.chunk",
        "created": created,
        "model": model,
        "choices": [
            {
                "index": 0,
                "delta": delta,
                "finish_reason": finish_reason,
            }
        ],
    }


def _new_stream_ids() -> tuple[str, int]:
    return f"chatcmpl-{uuid.uuid4().hex[:24]}", int(time.time())


def _sse_chunk(
    completion_id: str,
    created: int,
    model: str,
    delta: dict[str, Any],
    finish_reason: str | None = None,
) -> str:
    return _sse(
        json.dumps(
            _openai_chunk(
                completion_id=completion_id,
                created=created,
                model=model,
                delta=delta,
                finish_reason=finish_reason,
            )
        )
    )


def _extract_stream_delta_text(chunk: dict[str, Any]) -> tuple[str, str | None]:
    """Return (text, finish_reason) from an imported-model stream chunk."""
    choices = chunk.get("choices")
    if isinstance(choices, list) and choices:
        choice = choices[0] or {}
        finish_reason = choice.get("finish_reason")
        finish = finish_reason if isinstance(finish_reason, str) else None
        delta = choice.get("delta") or {}
        if isinstance(delta, dict):
            content = delta.get("content")
            if isinstance(content, str) and content:
                return content, finish
        message = choice.get("message") or {}
        if isinstance(message, dict):
            content = message.get("content")
            if isinstance(content, str) and content:
                return content, finish
        text = choice.get("text")
        if isinstance(text, str) and text:
            return text, finish

    for key in ("generation", "completion", "outputText", "text"):
        value = chunk.get(key)
        if isinstance(value, str) and value:
            return value, None

    outputs = chunk.get("outputs")
    if isinstance(outputs, list) and outputs:
        text = outputs[0].get("text")
        if isinstance(text, str) and text:
            return text, None

    return "", None


def _raise_stream_event_error(event: dict[str, Any]) -> None:
    for key in _STREAM_ERROR_KEYS:
        if key in event:
            message = (event[key] or {}).get("message") or key
            raise RuntimeError(message)


def _openai_sse_stream(
    model: str, deltas: Iterator[tuple[str, str | None]]
) -> Iterator[str]:
    completion_id, created = _new_stream_ids()
    yield _sse_chunk(completion_id, created, model, {"role": "assistant", "content": ""})
    finish_reason = "stop"
    for text, chunk_finish in deltas:
        if chunk_finish:
            finish_reason = chunk_finish
        if text:
            yield _sse_chunk(completion_id, created, model, {"content": text})
    yield _sse_chunk(completion_id, created, model, {}, finish_reason=finish_reason)
    yield _sse("[DONE]")


def _stream_invoke_model(
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float | None,
    top_p: float | None,
    model: str,
    bedrock_model_id: str,
) -> Iterator[str]:
    # Open Bedrock stream before emitting SSE so setup failures become HTTP 502.
    response = bedrock.invoke_model_with_response_stream(
        modelId=bedrock_model_id,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(
            _invoke_body(messages, max_tokens, temperature, top_p, stream=True)
        ),
    )
    event_stream = response.get("body")

    def deltas() -> Iterator[tuple[str, str | None]]:
        finish_reason: str | None = None
        for event in event_stream:
            chunk_event = event.get("chunk")
            if not chunk_event:
                _raise_stream_event_error(event)
                continue
            payload = json.loads(chunk_event["bytes"])
            text, chunk_finish = _extract_stream_delta_text(payload)
            if chunk_finish:
                finish_reason = chunk_finish
            if text:
                yield text, None
        yield "", finish_reason or "stop"

    yield from _openai_sse_stream(model, deltas())


def _stream_converse(
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float | None,
    top_p: float | None,
    model: str,
    bedrock_model_id: str,
) -> Iterator[str]:
    response = bedrock.converse_stream(
        **_converse_args(messages, max_tokens, temperature, top_p, bedrock_model_id)
    )
    event_stream = response.get("stream") or []

    def deltas() -> Iterator[tuple[str, str | None]]:
        finish_reason: str | None = None
        for event in event_stream:
            _raise_stream_event_error(event)
            if "contentBlockDelta" in event:
                delta = event["contentBlockDelta"].get("delta") or {}
                text = _converse_delta_text(delta)
                if text:
                    yield text, None
            elif "messageStop" in event:
                stop_reason = event["messageStop"].get("stopReason")
                finish_reason = "length" if stop_reason == "max_tokens" else "stop"
        yield "", finish_reason or "stop"

    yield from _openai_sse_stream(model, deltas())


def _messages_to_text(messages: list[dict[str, str]]) -> str:
    return "\n\n".join(m["content"] for m in messages if m.get("content"))


def _infer_minilm(messages: list[dict[str, str]]) -> dict[str, Any]:
    from minilm import classify

    result = classify(_messages_to_text(messages))
    return {
        "text": json.dumps(result, ensure_ascii=False),
        "usage": {
            "prompt_tokens": int(result.get("tokens", 0) or 0),
            "completion_tokens": 0,
        },
    }


def _stream_minilm(messages: list[dict[str, str]], model: str) -> Iterator[str]:
    inferred = _infer_minilm(messages)

    def deltas() -> Iterator[tuple[str, str | None]]:
        if inferred["text"]:
            yield inferred["text"], None
        yield "", "stop"

    yield from _openai_sse_stream(model, deltas())


def _run_inference(
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float | None,
    top_p: float | None,
    bedrock_model_id: str,
) -> dict[str, Any]:
    if _is_minilm(bedrock_model_id):
        return _infer_minilm(messages)
    if _is_imported_model(bedrock_model_id):
        return _infer_invoke_model(
            messages, max_tokens, temperature, top_p, bedrock_model_id
        )
    return _infer_converse(
        messages, max_tokens, temperature, top_p, bedrock_model_id
    )


def _stream_inference(
    messages: list[dict[str, str]],
    max_tokens: int,
    temperature: float | None,
    top_p: float | None,
    model: str,
    bedrock_model_id: str,
) -> Iterator[str]:
    if _is_minilm(bedrock_model_id):
        return _stream_minilm(messages, model)
    if _is_imported_model(bedrock_model_id):
        return _stream_invoke_model(
            messages, max_tokens, temperature, top_p, model, bedrock_model_id
        )
    return _stream_converse(
        messages, max_tokens, temperature, top_p, model, bedrock_model_id
    )


def _bedrock_error(exc: Exception) -> JSONResponse:
    if isinstance(exc, ClientError):
        detail = exc.response.get("Error", {}).get("Message", str(exc))
    else:
        detail = str(exc)
    return JSONResponse(
        status_code=502,
        content={"error": "bedrock request failed", "detail": detail},
    )


async def _parse_infer_payload(
    request: Request,
    x_api_key: str | None,
    authorization: str | None,
) -> _InferRequest | JSONResponse:
    if not _authorized(x_api_key, authorization):
        return _unauthorized()

    try:
        payload = await request.json()
    except Exception:  # noqa: BLE001
        return JSONResponse(status_code=400, content={"error": "invalid JSON body"})

    try:
        messages = _normalize_messages(payload)
        max_tokens, temperature, top_p = _parse_sampling(payload)
        response_model, bedrock_model_id = _resolve_model(payload.get("model"))
    except ValueError as exc:
        return JSONResponse(status_code=400, content={"error": str(exc)})

    return _InferRequest(
        messages,
        max_tokens,
        temperature,
        top_p,
        response_model,
        bedrock_model_id,
        bool(payload.get("stream")),
    )


def _as_sse(generator: Iterator[str]) -> StreamingResponse:
    first = next(generator)

    def event_stream() -> Iterator[str]:
        yield first
        try:
            yield from generator
        except Exception as exc:  # noqa: BLE001
            yield _sse(json.dumps({"error": "bedrock request failed", "detail": str(exc)}))
            yield _sse("[DONE]")

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


def _run_or_error(req: _InferRequest) -> dict[str, Any] | JSONResponse:
    try:
        return _run_inference(
            req.messages,
            req.max_tokens,
            req.temperature,
            req.top_p,
            req.bedrock_model_id,
        )
    except Exception as exc:  # noqa: BLE001
        return _bedrock_error(exc)


@app.options("/{full_path:path}")
async def options(full_path: str) -> Response:  # noqa: ARG001
    return Response(
        status_code=204,
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "content-type,x-api-key,authorization",
            "Access-Control-Allow-Methods": "POST,OPTIONS",
        },
    )


@app.post("/v1/chat/completions")
async def chat_completions(
    request: Request,
    x_api_key: str | None = Header(default=None),
    authorization: str | None = Header(default=None),
) -> Response:
    parsed = await _parse_infer_payload(request, x_api_key, authorization)
    if isinstance(parsed, JSONResponse):
        return parsed

    if parsed.stream:
        try:
            return _as_sse(
                _stream_inference(
                    parsed.messages,
                    parsed.max_tokens,
                    parsed.temperature,
                    parsed.top_p,
                    parsed.response_model,
                    parsed.bedrock_model_id,
                )
            )
        except Exception as exc:  # noqa: BLE001
            return _bedrock_error(exc)

    inferred = _run_or_error(parsed)
    if isinstance(inferred, JSONResponse):
        return inferred
    return JSONResponse(
        content=_openai_completion(
            parsed.response_model, inferred["text"], inferred["usage"]
        )
    )


@app.post("/")
@app.post("/infer")
async def infer(
    request: Request,
    x_api_key: str | None = Header(default=None),
    authorization: str | None = Header(default=None),
) -> Response:
    parsed = await _parse_infer_payload(request, x_api_key, authorization)
    if isinstance(parsed, JSONResponse):
        return parsed

    inferred = _run_or_error(parsed)
    if isinstance(inferred, JSONResponse):
        return inferred
    return JSONResponse(
        content=_legacy_infer_response(
            parsed.response_model, inferred["text"], inferred["usage"]
        )
    )
