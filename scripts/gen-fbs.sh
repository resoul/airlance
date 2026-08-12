#!/usr/bin/env bash
set -euo pipefail

if ! command -v flatc &> /dev/null; then
    echo "error: flatc not found. Install: brew install flatbuffers" >&2
    exit 1
fi

SCHEMA="proto/schema.fbs"
OUT_API_DIR="workspace/api/internal/protocol/generated"
OUT_SWIFT_DIR="workspace/macOS-swift/submodules/AirlanceClient/Sources/AirlanceClient/Protocol"

mkdir -p "$OUT_API_DIR"
flatc --go -o "$OUT_API_DIR" "$SCHEMA"

echo "generated Go code from $SCHEMA -> $OUT_API_DIR"

mkdir -p "$OUT_SWIFT_DIR"
flatc --swift -o "$OUT_SWIFT_DIR" "$SCHEMA"

echo "generated Swift code from $SCHEMA -> $OUT_SWIFT_DIR"




