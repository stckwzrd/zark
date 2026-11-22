#!/usr/bin/env bash
cd "$(dirname "$0")/.."
[ "$(uname -s)-$(uname -m)" = "Linux-x86_64" ] || { echo "ok   baremetal (skipped, needs x86-64 Linux)"; exit 0; }
VIBE=${VIBE:-./build/vibe}
command -v qemu-system-x86_64 >/dev/null && command -v objcopy >/dev/null || { echo "ok   baremetal (skipped, no qemu)"; exit 0; }
case $VIBE in /*) ;; *) VIBE=$PWD/$VIBE ;; esac
tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
for flags in "" "--llvm"; do
  if ! diff <(OUT=$tmp VIBE=$VIBE FLAGS=$flags examples/baremetal/run.sh 2>&1) tests/expected/baremetal.out >/dev/null; then
    echo "FAIL baremetal ${flags:-native}"; exit 1
  fi
done
echo "ok   baremetal (the kernel boots in QEMU, native and LLVM)"
