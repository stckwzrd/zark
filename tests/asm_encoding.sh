#!/usr/bin/env bash
cd "$(dirname "$0")/.."
[ "$(uname -s)-$(uname -m)" = "Linux-x86_64" ] || { echo "ok   asm encoding (skipped, needs x86-64 Linux)"; exit 0; }
ZARK=${ZARK:-./build/zark}
command -v objdump >/dev/null || { echo "ok   asm encoding (skipped, no objdump)"; exit 0; }
tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
for mode in --native --llvm; do
  $ZARK build tests/asm/privileged.zk $mode -o $tmp/p >/dev/null 2>&1 || { echo "FAIL asm encoding: build $mode"; exit 1; }
  objdump -d --no-show-raw-insn $tmp/p | grep -oE "\b(cli|sti|hlt|pause|mfence|lfence|sfence|lidt|lgdt|invlpg|wrmsr|rdmsr|rdtsc|in |out ).*" | sed -E 's/^(in|out)  *.*/\1/' | awk '{print $1}' | sort -u > $tmp/$mode.txt
done
for want in cli sti hlt pause mfence lfence sfence lidt lgdt invlpg wrmsr rdmsr in out; do
  grep -qx "$want" $tmp/--native.txt || { echo "FAIL asm encoding: native backend lacks '$want'"; exit 1; }
done
diff <(sort $tmp/--native.txt) <(sort $tmp/--llvm.txt) >/dev/null || { echo "FAIL asm encoding: backends disagree"; diff $tmp/--native.txt $tmp/--llvm.txt; exit 1; }
echo "ok   asm encoding (native and LLVM emit the same privileged instructions)"
