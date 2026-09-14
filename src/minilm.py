"""In-process MiniLM-L12-H384 classifier (WildGuardMix binary head)."""

from __future__ import annotations

import json
import struct
from pathlib import Path
from typing import Any

import numpy as np
from tokenizers import Tokenizer

LABELS = ("unharmful", "harmful")
MAX_LENGTH = 256
_EPS = 1e-12


def _model_dir() -> Path:
    here = Path(__file__).resolve().parent
    for path in (
        here / "MiniLM-L12-H384",
        here.parent / "models" / "MiniLM-L12-H384",
    ):
        if (path / "tokenizer.json").is_file() and (
            (path / "weights.npz").is_file() or (path / "model.safetensors").is_file()
        ):
            return path
    raise FileNotFoundError(
        "MiniLM-L12-H384 weights not packaged (tokenizer.json + weights.npz)"
    )


def _load_safetensors(path: Path) -> dict[str, np.ndarray]:
    dtypes = {"F32": np.float32, "F16": np.float16, "BF16": np.float16}
    with path.open("rb") as handle:
        header_len = struct.unpack("<Q", handle.read(8))[0]
        header = json.loads(handle.read(header_len))
        header.pop("__metadata__", None)
        data_start = 8 + header_len
        tensors: dict[str, np.ndarray] = {}
        for name, info in header.items():
            dtype = dtypes[info["dtype"]]
            start, end = info["data_offsets"]
            handle.seek(data_start + start)
            raw = handle.read(end - start)
            tensors[name] = np.frombuffer(raw, dtype=dtype).reshape(info["shape"]).astype(
                np.float32, copy=False
            )
    return tensors


def _load_weights(model_dir: Path) -> dict[str, np.ndarray]:
    npz_path = model_dir / "weights.npz"
    if npz_path.is_file():
        with np.load(npz_path) as bundle:
            return {name: bundle[name].astype(np.float32, copy=False) for name in bundle.files}
    return _load_safetensors(model_dir / "model.safetensors")


def _load_config(model_dir: Path) -> dict[str, Any]:
    return json.loads((model_dir / "config.json").read_text())


def _gelu(x: np.ndarray) -> np.ndarray:
    # BERT `gelu` (erf). Abramowitz–Stegun approximation.
    z = x / np.sqrt(2.0)
    sign = np.sign(z)
    az = np.abs(z)
    t = 1.0 / (1.0 + 0.3275911 * az)
    erf = sign * (
        1.0
        - (
            ((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t
            + 0.254829592
        )
        * t
        * np.exp(-az * az)
    )
    return 0.5 * x * (1.0 + erf)


def _layer_norm(x: np.ndarray, weight: np.ndarray, bias: np.ndarray) -> np.ndarray:
    mean = x.mean(axis=-1, keepdims=True)
    var = ((x - mean) ** 2).mean(axis=-1, keepdims=True)
    return weight * (x - mean) / np.sqrt(var + _EPS) + bias


def _linear(x: np.ndarray, weight: np.ndarray, bias: np.ndarray) -> np.ndarray:
    return x @ weight.T + bias


def _softmax(x: np.ndarray, axis: int = -1) -> np.ndarray:
    shifted = x - x.max(axis=axis, keepdims=True)
    exp = np.exp(shifted)
    return exp / exp.sum(axis=axis, keepdims=True)


def _self_attention(
    hidden: np.ndarray,
    weights: dict[str, np.ndarray],
    prefix: str,
    n_heads: int,
    head_dim: int,
) -> np.ndarray:
    query = _linear(
        hidden, weights[f"{prefix}attention.self.query.weight"],
        weights[f"{prefix}attention.self.query.bias"],
    )
    key = _linear(
        hidden, weights[f"{prefix}attention.self.key.weight"],
        weights[f"{prefix}attention.self.key.bias"],
    )
    value = _linear(
        hidden, weights[f"{prefix}attention.self.value.weight"],
        weights[f"{prefix}attention.self.value.bias"],
    )
    seq = hidden.shape[0]
    query = query.reshape(seq, n_heads, head_dim).transpose(1, 0, 2)
    key = key.reshape(seq, n_heads, head_dim).transpose(1, 0, 2)
    value = value.reshape(seq, n_heads, head_dim).transpose(1, 0, 2)
    scores = (query @ key.transpose(0, 2, 1)) / np.sqrt(head_dim)
    context = (_softmax(scores, axis=-1) @ value).transpose(1, 0, 2).reshape(seq, -1)
    return _linear(
        context,
        weights[f"{prefix}attention.output.dense.weight"],
        weights[f"{prefix}attention.output.dense.bias"],
    )


def _encoder_layer(
    hidden: np.ndarray,
    weights: dict[str, np.ndarray],
    layer: int,
    n_heads: int,
    head_dim: int,
) -> np.ndarray:
    prefix = f"bert.encoder.layer.{layer}."
    attn = _self_attention(hidden, weights, prefix, n_heads, head_dim)
    hidden = _layer_norm(
        hidden + attn,
        weights[f"{prefix}attention.output.LayerNorm.weight"],
        weights[f"{prefix}attention.output.LayerNorm.bias"],
    )
    intermediate = _gelu(
        _linear(
            hidden,
            weights[f"{prefix}intermediate.dense.weight"],
            weights[f"{prefix}intermediate.dense.bias"],
        )
    )
    output = _linear(
        intermediate,
        weights[f"{prefix}output.dense.weight"],
        weights[f"{prefix}output.dense.bias"],
    )
    return _layer_norm(
        hidden + output,
        weights[f"{prefix}output.LayerNorm.weight"],
        weights[f"{prefix}output.LayerNorm.bias"],
    )


def _forward(
    input_ids: np.ndarray,
    token_type_ids: np.ndarray,
    weights: dict[str, np.ndarray],
    config: dict[str, Any],
) -> np.ndarray:
    hidden_size = int(config["hidden_size"])
    n_heads = int(config["num_attention_heads"])
    n_layers = int(config["num_hidden_layers"])
    head_dim = hidden_size // n_heads
    seq = input_ids.shape[0]
    hidden = (
        weights["bert.embeddings.word_embeddings.weight"][input_ids]
        + weights["bert.embeddings.position_embeddings.weight"][np.arange(seq)]
        + weights["bert.embeddings.token_type_embeddings.weight"][token_type_ids]
    )
    hidden = _layer_norm(
        hidden,
        weights["bert.embeddings.LayerNorm.weight"],
        weights["bert.embeddings.LayerNorm.bias"],
    )
    for layer in range(n_layers):
        hidden = _encoder_layer(hidden, weights, layer, n_heads, head_dim)
    pooled = np.tanh(
        _linear(
            hidden[0],
            weights["bert.pooler.dense.weight"],
            weights["bert.pooler.dense.bias"],
        )
    )
    return _linear(pooled, weights["classifier.weight"], weights["classifier.bias"])


class _Session:
    def __init__(self, model_dir: Path) -> None:
        self.config = _load_config(model_dir)
        self.weights = _load_weights(model_dir)
        tokenizer = Tokenizer.from_file(str(model_dir / "tokenizer.json"))
        tokenizer.no_padding()
        tokenizer.enable_truncation(max_length=MAX_LENGTH)
        self.tokenizer = tokenizer

    def classify(self, text: str) -> dict[str, Any]:
        encoded = self.tokenizer.encode(text)
        input_ids = np.asarray(encoded.ids, dtype=np.int64)
        token_type_ids = np.asarray(encoded.type_ids, dtype=np.int64)
        logits = _forward(input_ids, token_type_ids, self.weights, self.config)
        probs = _softmax(logits)
        index = int(probs.argmax())
        labels = LABELS
        if len(probs) != len(labels):
            labels = tuple(f"label_{i}" for i in range(len(probs)))
        return {
            "label": labels[index],
            "score": float(probs[index]),
            "probs": {labels[i]: float(probs[i]) for i in range(len(labels))},
            "tokens": int(input_ids.shape[0]),
        }


_SESSION: _Session | None = None


def classify(text: str) -> dict[str, Any]:
    global _SESSION
    if _SESSION is None:
        _SESSION = _Session(_model_dir())
    return _SESSION.classify(text)
