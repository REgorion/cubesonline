#!/usr/bin/env bash
set -eu

# Point this to where you installed emscripten. Optional on systems that already
# have `emcc` in the path.
EMSCRIPTEN_SDK_DIR="$HOME/repos/emsdk"
OUT_DIR="build/web"

mkdir -p $OUT_DIR

BUILD_VER=$(./bump_version.sh)

export EMSDK_QUIET=1
[[ -f "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh" ]] && . "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh"

# Note RAYLIB_WASM_LIB=env.o -- env.o is an internal WASM object file. You can
# see how RAYLIB_WASM_LIB is used inside <odin>/vendor/raylib/raylib.odin.
#
# The emcc call will be fed the actual raylib library file. That stuff will end
# up in env.o
#
# Note that there is a rayGUI equivalent: -define:RAYGUI_WASM_LIB=env.o
../Odin/odin build source/main_web -target:js_wasm32 -build-mode:obj -define:RAYLIB_WASM_LIB=env.o -define:RAYGUI_WASM_LIB=env.o -out:$OUT_DIR/game.o

ODIN_PATH=$(../Odin/odin root)

cp $ODIN_PATH/core/sys/wasm/js/odin.js $OUT_DIR

files="$OUT_DIR/game.wasm.o ${ODIN_PATH}/vendor/raylib/wasm/libraylib.a ${ODIN_PATH}/vendor/raylib/wasm/libraygui.a"

Byte=1
Kilobyte=$((1024 * Byte))
Megabyte=$((1024 * Kilobyte))

STACK=$((32 * Megabyte))
HEAP=$((600 * Megabyte))

# index_template.html contains the javascript code that calls the procedures in
# source/main_web/main_web.odin
cp "source/main_web/ws_client.js" $OUT_DIR
flags=" -sTOTAL_MEMORY=$HEAP -sSTACK_SIZE=$STACK -sWASM_BIGINT -sWARN_ON_UNDEFINED_SYMBOLS=0 -sMIN_WEBGL_VERSION=2 -sUSE_GLFW=3 --shell-file source/main_web/index_template.html --preload-file assets" 
# For debugging: Add `-g` to `emcc` (gives better error callstack in chrome)
emsdk/upstream/emscripten/emcc -o $OUT_DIR/index.html $files $flags

rm $OUT_DIR/game.wasm.o

echo "Web build $BUILD_VER created in ${OUT_DIR}"
