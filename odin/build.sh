#!/bin/bash
# Builds the js_wasm32 version into ./out (serve it with any static server, e.g. python3 -m http.server -d out).
set -e
cd "$(dirname "$0")"
rm -rf out && mkdir out
odin build . -target:js_wasm32 -out:out/game.wasm -o:speed
cp "$(odin root)/core/sys/wasm/js/odin.js" out/
cp web/* out/
