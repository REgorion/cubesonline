#!/usr/bin/env bash
set -eu

# This script creates an optimized release build.

OUT_DIR="build/release"
mkdir -p "$OUT_DIR"

BUILD_VER=$(./bump_version.sh)

../Odin/odin build source/main_release -out:$OUT_DIR/game_release.bin -no-bounds-check -o:speed
cp -R assets $OUT_DIR
echo "Release build $BUILD_VER created in $OUT_DIR"