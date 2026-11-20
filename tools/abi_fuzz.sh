#!/usr/bin/env bash
# Differential test of struct passing across the C ABI: random structs and extern functions,
# compiled by Vibe on every backend and compared with the same calls compiled by clang.
#   tools/abi_fuzz.sh [first_seed] [last_seed]
set -u
VIBE=$(realpath "${VIBE:-build/vibe}")
GEN=$(realpath "$(dirname "$0")/abi_fuzz.py")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T"
bad=0; n=0
for seed in $(seq "${1:-1}" "${2:-100}"); do
  python3 "$GEN" "$seed"
  clang -w -O1 ref.c lib.c -o ref || { echo "seed $seed: reference build failed"; continue; }
  want=$(./ref | sed 's/-0.000000/0.000000/')
  n=$((n+1))
  for fl in "" "--llvm" "-O"; do
    got=$("$VIBE" run p.vibe lib.c $fl 2>&1 | sed 's/-0.000000/0.000000/')
    if [ "$got" != "$want" ]; then bad=$((bad+1)); echo "MISMATCH seed=$seed flags='$fl'"; fi
  done
done
echo "programs=$n mismatches=$bad"
[ $bad -eq 0 ]
