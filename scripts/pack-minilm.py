#!/usr/bin/env python3
"""Convert MiniLM safetensors to a compact float16 npz for the Lambda zip."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import numpy as np

DTYPES = {"F32": np.float32, "F16": np.float16, "BF16": np.float16}


def load_safetensors(path: Path) -> dict[str, np.ndarray]:
    with path.open("rb") as handle:
        header_len = struct.unpack("<Q", handle.read(8))[0]
        header = json.loads(handle.read(header_len))
        header.pop("__metadata__", None)
        data_start = 8 + header_len
        tensors: dict[str, np.ndarray] = {}
        for name, info in header.items():
            start, end = info["data_offsets"]
            handle.seek(data_start + start)
            raw = handle.read(end - start)
            tensors[name] = np.frombuffer(raw, dtype=DTYPES[info["dtype"]]).reshape(
                info["shape"]
            )
    return tensors


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} MODEL_DIR DEST_NPZ")
    model_dir = Path(sys.argv[1])
    dest = Path(sys.argv[2])
    src = model_dir / "model.safetensors"
    existing = model_dir / "weights.npz"
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not src.is_file() and existing.is_file():
        dest.write_bytes(existing.read_bytes())
        print(f"Copied {existing} → {dest} ({dest.stat().st_size} bytes)")
        return
    if not src.is_file():
        raise SystemExit(f"missing {src}")
    tensors = {name: array.astype(np.float16) for name, array in load_safetensors(src).items()}
    np.savez(dest, **tensors)
    print(f"Wrote {dest} ({dest.stat().st_size} bytes, {len(tensors)} tensors)")


if __name__ == "__main__":
    main()
