#!/bin/bash
# Builds whisper.cpp (Vendor/whisper.cpp submodule) as static libraries
# for linking into the DaemonFlow app target.
#
# Output: Vendor/whisper-libs/*.a
# Re-run after updating the submodule. Requires cmake (brew install cmake)
# and a full Xcode install (Metal toolchain).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$PROJECT_DIR/Vendor/whisper.cpp"
BUILD_DIR="$SRC_DIR/build-daemonflow"
LIB_DIR="$PROJECT_DIR/Vendor/whisper-libs"

if [[ -d /Applications/Xcode-beta.app && ! -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON

cmake --build "$BUILD_DIR" --config Release -j "$(sysctl -n hw.ncpu)"

mkdir -p "$LIB_DIR"
find "$BUILD_DIR" -name '*.a' -exec cp {} "$LIB_DIR/" \;

echo "--- Static libraries in $LIB_DIR:"
ls -lh "$LIB_DIR"
