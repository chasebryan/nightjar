#!/bin/sh
# Build linuxbox.wasm with the production
# wasi-sdk (34) on this bench.
set -e
SDK="$HOME/workspace/wasi-bench/wasi-sdk-34.0-x86_64-linux"
"$SDK/bin/clang" --target=wasm32-wasip1 -O2 \
  -Wl,--strip-all \
  -o linuxbox.wasm linuxbox.c
ls -la linuxbox.wasm
