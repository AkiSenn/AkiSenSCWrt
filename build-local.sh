#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$HOME/akisen-mtk-build}"
: "${WIFI_PASSWORD:?Set WIFI_PASSWORD privately in the environment}"
python3 "$ROOT/scripts/checkout-source.py" "$BUILD_DIR"
cd "$BUILD_DIR"
./scripts/feeds update -a
./scripts/feeds install -a
python3 "$ROOT/scripts/prepare.py"
make download -j8 || make download -j1 V=s
make -j"${JOBS:-$(nproc)}" || make -j1 V=s
python3 "$ROOT/scripts/collect.py" "$BUILD_DIR/private-output"
