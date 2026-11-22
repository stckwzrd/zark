#!/usr/bin/env bash
# Compile-time benchmark: the same 10k-line program in Zark and C, built to an executable.
set -euo pipefail
cd "$(dirname "$0")"
ZARK=${ZARK:-../build/zark}
python3 gen.py 500
med() { # median wall time (ms) of 5 runs
  for i in 1 2 3 4 5; do s=$(date +%s%N); "$@" >/dev/null 2>&1; e=$(date +%s%N); echo $(( (e - s) / 1000000 )); done | sort -n | sed -n 3p
}
printf "%-26s %6s ms\n" "zark (native backend)" "$(med $ZARK build w.zk -o wv)"
printf "%-26s %6s ms\n" "gcc -O0"                "$(med gcc -O0 w.c -o wg)"
printf "%-26s %6s ms\n" "clang -O0"              "$(med clang -O0 w.c -o wc)"
./wv; ./wg; ./wc
