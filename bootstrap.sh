#!/usr/bin/env bash
# Full bootstrap: Zig stage0 -> Vibe stage1 -> stage2 -> stage3, then check the fixed point.
set -euo pipefail
cd "$(dirname "$0")"
ZIG=zig; command -v zig >/dev/null || ZIG="python3 -m ziglang"
mkdir -p build

echo "== stage0: Zig reference compiler"
$ZIG build -Doptimize=ReleaseFast
S0=zig-out/bin/vibe

echo "== stage1: Vibe compiler built by stage0"
$S0 build selfhost/main.vibe --release -o build/stage1
echo "== stage2: Vibe compiler built by itself"
build/stage1 build selfhost/main.vibe --release -o build/stage2
echo "== stage3: and again"
build/stage2 build selfhost/main.vibe --release -o build/stage3

build/stage2 ir selfhost/main.vibe > build/stage2.ll
build/stage3 ir selfhost/main.vibe > build/stage3.ll
if cmp -s build/stage2.ll build/stage3.ll && cmp -s build/stage2 build/stage3; then
  echo "== fixed point reached: stage2 == stage3 ($(wc -l < build/stage2.ll) lines of IR, sha256 $(sha256sum build/stage2 | cut -c1-16))"
else
  echo "!! stage2 and stage3 differ"; exit 1
fi

echo "== native backend: compiler built without LLVM, then by itself"
build/stage2 build selfhost/main.vibe --native -o build/native1
build/native1 build selfhost/main.vibe --native -o build/native2
build/native2 build selfhost/main.vibe --native -o build/native3
if cmp -s build/native2 build/native3; then echo "== native fixed point reached: native2 == native3"; else echo "!! native2 and native3 differ"; exit 1; fi
VIBE=build/native2 tests/run.sh | tail -1

echo "== test suite with the self-hosted compiler"
VIBE=build/stage2 tests/run.sh
cp build/stage2 build/vibe
echo "== done: build/vibe is the self-hosted compiler"
