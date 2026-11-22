#!/usr/bin/env bash
cd "$(dirname "$0")/.."
[ "$(uname -s)-$(uname -m)" = "Linux-x86_64" ] || { echo "ok   baremetal (skipped, needs x86-64 Linux)"; exit 0; }
ZARK=${ZARK:-./build/zark}
command -v qemu-system-x86_64 >/dev/null && command -v objcopy >/dev/null || { echo "ok   baremetal (skipped, no qemu)"; exit 0; }
case $ZARK in /*) ;; *) ZARK=$PWD/$ZARK ;; esac
tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
for flags in "" "--llvm"; do
  if ! diff <(OUT=$tmp ZARK=$ZARK FLAGS=$flags examples/baremetal/run.sh 2>&1) tests/expected/baremetal.out >/dev/null; then
    echo "FAIL baremetal ${flags:-native}"; exit 1
  fi
done
echo "ok   baremetal (the kernel boots in QEMU, native and LLVM)"
