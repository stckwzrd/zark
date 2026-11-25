#!/usr/bin/env bash
# Build the self-hosted compiler with AddressSanitizer and UndefinedBehaviorSanitizer.
# Uses the same runtime and libraries as bootstrap.sh.
#   ZARK=build/stage2 tools/build_asan.sh
#   ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 ZARK=build/zark-asan tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ZARK=${ZARK:-build/stage2}
"$ZARK" ir selfhost/main.zk > build/zk-asan.ll
clang -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer \
    -Wno-override-module build/zk-asan.ll std/rt.c \
    -o build/zark-asan -lm -lpthread -ldl
echo "built build/zark-asan"
