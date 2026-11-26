#!/usr/bin/env bash
# Runtime benchmark: examples/bench.zk on the native and LLVM backends against C.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd .. && pwd)
ZARK=${ZARK:-$ROOT/build/zark}
if [ ! -x "$ZARK" ] && [ -x "$ROOT/$ZARK" ]; then ZARK="$ROOT/$ZARK"; fi
OUT="$ROOT/build/bench"
mkdir -p "$OUT"

"$ZARK" build "$ROOT/examples/bench.zk" -o "$OUT/zark-native"
"$ZARK" build "$ROOT/examples/bench.zk" --native --release -o "$OUT/zark-native-rel"
"$ZARK" build "$ROOT/examples/bench.zk" -O -o "$OUT/zark-llvm"
"$ZARK" build "$ROOT/examples/bench.zk" -O --release -o "$OUT/zark-llvm-rel"
gcc -O0 runtime.c -o "$OUT/c-gcc-O0"
gcc -O2 runtime.c -o "$OUT/c-gcc-O2"
clang -O0 runtime.c -o "$OUT/c-clang-O0"
clang -O2 runtime.c -o "$OUT/c-clang-O2"

for b in zark-native zark-native-rel zark-llvm zark-llvm-rel c-gcc-O0 c-gcc-O2 c-clang-O0 c-clang-O2; do
    echo "== $b"
    "$OUT/$b"
done
