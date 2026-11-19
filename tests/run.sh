#!/usr/bin/env bash
# Runs all examples and compares against expected output.
cd "$(dirname "$0")/.."
VIBE=${VIBE:-./build/vibe}
pass=0; fail=0
check() { # name, cmd...
  local name=$1; shift
  if diff -u "tests/expected/$name.out" <("$@" 2>&1) >/dev/null; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name"; diff -u "tests/expected/$name.out" <("$@" 2>&1) | head -20; fi
}
for n in hello features edge memory funcs unions minilang stdlib2 io cpp_style driver memtool interfaces; do check $n $VIBE run examples/$n.vibe $FLAGS; done
check interop $VIBE run examples/interop/main.vibe examples/interop/mathlib.c examples/interop/engine.cpp $FLAGS
for f in tests/errors/*.vibe; do
  if $VIBE run "$f" >/dev/null 2>&1; then fail=$((fail+1)); echo "FAIL $f (expected an error)"; else pass=$((pass+1)); echo "ok   $f (rejected)"; fi
done
tok_bad=0
for f in examples/*.vibe examples/interop/*.vibe tests/errors/*.vibe; do
  n=$(echo ${f%.vibe} | tr / _)
  cmp -s <($VIBE tokens $f) tests/tokens/$n.tok || { tok_bad=1; echo "tokens differ: $f"; }
done
if [ $tok_bad -eq 0 ]; then pass=$((pass+1)); echo "ok   tokens match tests/tokens ($(ls tests/tokens | wc -l) files)"; else fail=$((fail+1)); echo "FAIL tokens"; fi
if VIBE=$VIBE tests/baremetal.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if VIBE=$VIBE tests/asm_encoding.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
