#!/usr/bin/env python3
"""Normalize Wan finetune safetensors tensor names for stable-diffusion.cpp.

Some ComfyUI-oriented Wan 2.2 finetunes store diffusion tensors with a
`model.diffusion_model.` prefix. stable-diffusion.cpp adds its own prefix when
loading files passed through --diffusion-model / --high-noise-diffusion-model,
which produces names it cannot match during metadata validation.

This tool strips only that leading tensor-name prefix from the safetensors JSON
header. Tensor data is not copied or rewritten. The original header is saved
next to the model and can be restored with --restore.
"""

from __future__ import annotations

import argparse
import json
import os
import struct
import sys
from pathlib import Path

PREFIX = "model.diffusion_model."
MAX_HEADER_BYTES = 128 * 1024 * 1024
BACKUP_SUFFIX = ".sdcpp-header-backup"


def default_models() -> list[Path]:
    root = Path.home() / "AI/ComfyUI/models/diffusion_models"
    return [
        root / "smoothMixWan2214BI2V_i2vV20Low.safetensors",
        root / "smoothMixWan2214BI2V_i2vV20High.safetensors",
    ]


def read_header(file_obj) -> tuple[bytes, int, bytes, dict]:
    length_bytes = file_obj.read(8)
    if len(length_bytes) != 8:
        raise ValueError("file is too small to be a safetensors file")

    header_len = struct.unpack("<Q", length_bytes)[0]
    if header_len <= 0 or header_len > MAX_HEADER_BYTES:
        raise ValueError(f"invalid safetensors header length: {header_len}")

    header_bytes = file_obj.read(header_len)
    if len(header_bytes) != header_len:
        raise ValueError("truncated safetensors header")

    try:
        header = json.loads(header_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"invalid safetensors JSON header: {exc}") from exc

    if not isinstance(header, dict):
        raise ValueError("safetensors header is not a JSON object")

    return length_bytes, header_len, header_bytes, header


def write_backup(path: Path, original: bytes) -> Path:
    backup = path.with_name(path.name + BACKUP_SUFFIX)
    if backup.exists():
        return backup

    fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(original)
            out.flush()
            os.fsync(out.fileno())
    except Exception:
        try:
            backup.unlink(missing_ok=True)
        finally:
            raise
    return backup


def normalize(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)

    with path.open("r+b") as model:
        length_bytes, header_len, old_header_bytes, header = read_header(model)

        tensor_keys = [key for key in header if key != "__metadata__"]
        prefixed = [key for key in tensor_keys if key.startswith(PREFIX)]

        if not prefixed:
            print(f"[ OK ] {path.name}: tensor names already normalized")
            return

        normalized: dict = {}
        for key, value in header.items():
            new_key = key
            if key != "__metadata__" and key.startswith(PREFIX):
                new_key = key[len(PREFIX) :]

            if new_key in normalized:
                raise ValueError(
                    f"renaming {key!r} would collide with existing tensor {new_key!r}"
                )
            normalized[new_key] = value

        new_header = json.dumps(
            normalized,
            separators=(",", ":"),
            ensure_ascii=False,
        ).encode("utf-8")

        if len(new_header) > header_len:
            raise ValueError(
                "normalized header unexpectedly grew beyond the original header; refusing to rewrite"
            )

        backup = write_backup(path, length_bytes + old_header_bytes)
        padded_header = new_header + (b" " * (header_len - len(new_header)))

        try:
            model.seek(8)
            model.write(padded_header)
            model.flush()
            os.fsync(model.fileno())

            model.seek(0)
            _, verify_len, _, verify_header = read_header(model)
            if verify_len != header_len:
                raise ValueError("header length changed unexpectedly")
            if any(
                key.startswith(PREFIX)
                for key in verify_header
                if key != "__metadata__"
            ):
                raise ValueError("prefix remains after rewrite")
        except Exception:
            model.seek(0)
            original = backup.read_bytes()
            model.write(original)
            model.flush()
            os.fsync(model.fileno())
            raise

    print(
        f"[ OK ] {path.name}: stripped {PREFIX!r} from {len(prefixed)} tensor names"
    )
    print(f"       backup: {backup}")


def restore(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)

    backup = path.with_name(path.name + BACKUP_SUFFIX)
    if not backup.is_file():
        raise FileNotFoundError(f"no header backup found: {backup}")

    original = backup.read_bytes()
    if len(original) < 9:
        raise ValueError(f"invalid header backup: {backup}")

    header_len = struct.unpack("<Q", original[:8])[0]
    if len(original) != 8 + header_len:
        raise ValueError(f"header backup length does not match: {backup}")

    with path.open("r+b") as model:
        model.seek(0)
        model.write(original)
        model.flush()
        os.fsync(model.fileno())

    print(f"[ OK ] {path.name}: restored original safetensors header")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fix Wan finetune tensor-name prefixes for stable-diffusion.cpp"
    )
    parser.add_argument(
        "models",
        nargs="*",
        type=Path,
        help="safetensors files to fix; defaults to the SmoothMix V2 LOW/HIGH files",
    )
    parser.add_argument(
        "--restore",
        action="store_true",
        help="restore the original headers from .sdcpp-header-backup files",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    models = args.models or default_models()

    failed = False
    for model in models:
        try:
            if args.restore:
                restore(model.expanduser())
            else:
                normalize(model.expanduser())
        except Exception as exc:
            failed = True
            print(f"[FAIL] {model}: {exc}", file=sys.stderr)

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
