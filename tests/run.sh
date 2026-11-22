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
names="hello features edge memory funcs unions minilang stdlib2 io cpp_style interfaces classes operators_oop checks simd align_structs async_echo"
x86=0; [ "$(uname -m)" = x86_64 ] && x86=1
linux=0; [ "$(uname -s)" = Linux ] && linux=1
[ $x86 = 1 ] && names="$names driver"
[ $linux = 1 ] && names="$names memtool"
for n in $names; do check $n $VIBE run examples/$n.vibe $FLAGS; done
check showcase $VIBE run examples/showcase/main.vibe $FLAGS
check showcase_tests $VIBE test examples/showcase/main.vibe $FLAGS
check showcase_vec $VIBE test examples/showcase/vec.vibe $FLAGS
check interop $VIBE run examples/interop/main.vibe examples/interop/mathlib.c examples/interop/engine.cpp $FLAGS
[ $x86 = 1 ] && check abi $VIBE run tests/abi/main.vibe tests/abi/lib.c $FLAGS
for n in ints memory nan move borrow comptime mulcheck iterate threads flow flow2 alias_comptime narrow_div async_names async_basic async_try async_flow async_borrows; do check edge_$n $VIBE run tests/edge/$n.vibe $FLAGS; done
for f in tests/panics/*.vibe; do
  n=panic_$(basename $f .vibe)
  if out=$($VIBE run "$f" $FLAGS 2>&1); then fail=$((fail+1)); echo "FAIL $f (expected a panic)"
  elif [ "$(echo "$out" | sed 's/<std>:[0-9]*/<std>/')" = "$(cat tests/expected/$n.out)" ]; then pass=$((pass+1)); echo "ok   $n"
  else fail=$((fail+1)); echo "FAIL $n"; diff <(echo "$out") tests/expected/$n.out | head -10; fi
done
for f in tests/errors/*.vibe; do
  if $VIBE run "$f" >/dev/null 2>&1; then fail=$((fail+1)); echo "FAIL $f (expected an error)"; else pass=$((pass+1)); echo "ok   $f (rejected)"; fi
done
for f in tests/std/*.vibe; do
  if out=$($VIBE test "$f" $FLAGS 2>&1); then pass=$((pass+1)); echo "ok   $f ($(echo "$out" | tail -1))"
  else fail=$((fail+1)); echo "FAIL $f"; echo "$out" | grep -v "^ok" | head -20; fi
done
tok_bad=0
for f in examples/*.vibe examples/interop/*.vibe tests/errors/*.vibe; do
  n=$(echo ${f%.vibe} | tr / _)
  cmp -s <($VIBE tokens $f) tests/tokens/$n.tok || { tok_bad=1; echo "tokens differ: $f"; }
done
if [ $tok_bad -eq 0 ]; then pass=$((pass+1)); echo "ok   tokens match tests/tokens ($(ls tests/tokens | wc -l) files)"; else fail=$((fail+1)); echo "FAIL tokens"; fi
if VIBE=$VIBE tests/baremetal.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if VIBE=$VIBE tests/project.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if VIBE=$VIBE tests/asm_encoding.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if VIBE=$VIBE tests/scale.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
