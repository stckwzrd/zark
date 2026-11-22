#!/usr/bin/env bash
# Runs all examples and compares against expected output.
cd "$(dirname "$0")/.."
ZARK=${ZARK:-./build/zark}
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
for n in $names; do check $n $ZARK run examples/$n.zk $FLAGS; done
check showcase $ZARK run examples/showcase/main.zk $FLAGS
check showcase_tests $ZARK test examples/showcase/main.zk $FLAGS
check showcase_vec $ZARK test examples/showcase/vec.zk $FLAGS
check interop $ZARK run examples/interop/main.zk examples/interop/mathlib.c examples/interop/engine.cpp $FLAGS
[ $x86 = 1 ] && check abi $ZARK run tests/abi/main.zk tests/abi/lib.c $FLAGS
for n in ints memory nan move borrow comptime mulcheck iterate threads flow flow2 alias_comptime narrow_div async_names async_basic async_try async_flow async_borrows async_infer; do check edge_$n $ZARK run tests/edge/$n.zk $FLAGS; done
for f in tests/panics/*.zk; do
  n=panic_$(basename $f .zk)
  if out=$($ZARK run "$f" $FLAGS 2>&1); then fail=$((fail+1)); echo "FAIL $f (expected a panic)"
  elif [ "$(echo "$out" | sed 's/<std>:[0-9]*/<std>/')" = "$(cat tests/expected/$n.out)" ]; then pass=$((pass+1)); echo "ok   $n"
  else fail=$((fail+1)); echo "FAIL $n"; diff <(echo "$out") tests/expected/$n.out | head -10; fi
done
for f in tests/errors/*.zk; do
  if $ZARK run "$f" >/dev/null 2>&1; then fail=$((fail+1)); echo "FAIL $f (expected an error)"; else pass=$((pass+1)); echo "ok   $f (rejected)"; fi
done
for f in tests/std/*.zk; do
  if out=$($ZARK test "$f" $FLAGS 2>&1); then pass=$((pass+1)); echo "ok   $f ($(echo "$out" | tail -1))"
  else fail=$((fail+1)); echo "FAIL $f"; echo "$out" | grep -v "^ok" | head -20; fi
done
tok_bad=0
for f in examples/*.zk examples/interop/*.zk tests/errors/*.zk; do
  n=$(echo ${f%.zk} | tr / _)
  cmp -s <($ZARK tokens $f) tests/tokens/$n.tok || { tok_bad=1; echo "tokens differ: $f"; }
done
if [ $tok_bad -eq 0 ]; then pass=$((pass+1)); echo "ok   tokens match tests/tokens ($(ls tests/tokens | wc -l) files)"; else fail=$((fail+1)); echo "FAIL tokens"; fi
if ZARK=$ZARK tests/baremetal.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if ZARK=$ZARK tests/project.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if ZARK=$ZARK tests/cbuild.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if ZARK=$ZARK tests/cbind.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if ZARK=$ZARK tests/asm_encoding.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if ZARK=$ZARK tests/scale.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
