#!/usr/bin/env bash
# Runs all examples and compares against expected output.
cd "$(dirname "$0")/.."
ZARK=${ZARK:-./build/zark}
command -v timeout >/dev/null || timeout() { shift; "$@"; }
pass=0; fail=0
normstd() { sed -E 's#(<std>[^ :]*):[0-9]+#\1#g'; }
check_out=$(mktemp)
trap 'rm -f "$check_out"' EXIT
check() { # name, cmd...  (an optional tests/expected/<name>.rc sets the exit code)
  local name=$1 rc want_rc=0; shift
  if [ -f "tests/expected/$name.rc" ]; then want_rc=$(cat "tests/expected/$name.rc"); fi
  "$@" >"$check_out" 2>&1; rc=$?
  if [ $rc -ne $want_rc ]; then
    fail=$((fail+1)); echo "FAIL $name (exit $rc, expected $want_rc)"
    tail -20 "$check_out"
    return
  fi
  if diff -u "tests/expected/$name.out" "$check_out" >/dev/null; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name"; diff -u "tests/expected/$name.out" "$check_out" | head -20; fi
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
{ [ $x86 = 1 ] || [ "$(uname -m)" = aarch64 ] || [ "$(uname -m)" = arm64 ]; } && check abi $ZARK run tests/abi/main.zk tests/abi/lib.c $FLAGS
if [ $x86 = 1 ] && [ $linux = 1 ]; then
  if ZARK="$ZARK" python3 tests/abi/fuzz/fuzz.py --quick --strict --backends native,llvm,O >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   abi fuzz"
  else fail=$((fail+1)); echo "FAIL abi fuzz"; ZARK="$ZARK" python3 tests/abi/fuzz/fuzz.py --quick --strict --backends native,llvm,O 2>&1 | tail -20; fi
  if ZARK="$ZARK" python3 tests/abi/fuzz/fuzz.py --ir-oracle aarch64,arm64-apple >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   abi ir oracle aarch64"
  else fail=$((fail+1)); echo "FAIL abi ir oracle aarch64"; ZARK="$ZARK" python3 tests/abi/fuzz/fuzz.py --ir-oracle aarch64,arm64-apple 2>&1 | tail -20; fi
  if ZARK="$ZARK" python3 tools/fuzz_prog.py --quick >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   fuzz_prog"
  else fail=$((fail+1)); echo "FAIL fuzz_prog"; ZARK="$ZARK" python3 tools/fuzz_prog.py --quick 2>&1 | tail -40; fi
  if ZARK="$ZARK" python3 tools/fuzz_crash.py --quick >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   fuzz_crash"
  else fail=$((fail+1)); echo "FAIL fuzz_crash"; ZARK="$ZARK" python3 tools/fuzz_crash.py --quick 2>&1 | tail -30; fi
  if ZARK="$ZARK" python3 tools/fuzz_lsp.py --quick >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   fuzz_lsp"
  else fail=$((fail+1)); echo "FAIL fuzz_lsp"; ZARK="$ZARK" python3 tools/fuzz_lsp.py --quick 2>&1 | tail -20; fi
  if ZARK="$ZARK" python3 tools/fuzz_lsp.py --count 1 --seed 5111 >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   fuzz_lsp regress"
  else fail=$((fail+1)); echo "FAIL fuzz_lsp regress"; ZARK="$ZARK" python3 tools/fuzz_lsp.py --count 1 --seed 5111 2>&1 | tail -10; fi
  if ZARK="$ZARK" python3 tools/fuzz_own.py --quick >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   fuzz_own"
  else fail=$((fail+1)); echo "FAIL fuzz_own"; ZARK="$ZARK" python3 tools/fuzz_own.py --quick 2>&1 | tail -30; fi
fi
if [ "$(uname -m)" = aarch64 ] || [ "$(uname -m)" = arm64 ]; then
  if out=$(ZARK="$ZARK" python3 tests/abi/fuzz/fuzz.py --strict --backends llvm,O 2>&1); then pass=$((pass+1)); echo "ok   abi fuzz"
  else fail=$((fail+1)); echo "FAIL abi fuzz"; echo "$out" | grep -v "PASS     PASS" | tail -40; fi
fi
for n in ints memory nan move move_resource parse_types zero_init async_result async_join closure_capture borrow borrow_elem comptime mulcheck iterate fn_struct threads flow flow2 alias_comptime narrow_div async_names async_basic async_try async_flow async_borrows async_infer async_cancel fwd_types; do check edge_$n $ZARK run tests/edge/$n.zk $FLAGS; done
for f in tests/panics/*.zk; do
  n=panic_$(basename $f .zk)
  out=$($ZARK run "$f" $FLAGS 2>&1); rc=$?
  if [ $rc -eq 0 ]; then fail=$((fail+1)); echo "FAIL $f (expected a panic)"
  elif [ $rc -ne 1 ]; then fail=$((fail+1)); echo "FAIL $f (exit $rc, expected a panic)"
  elif [ "$(printf '%s\n' "$out" | normstd)" = "$(normstd < "tests/expected/$n.out")" ]; then pass=$((pass+1)); echo "ok   $n"
  else fail=$((fail+1)); echo "FAIL $n"; diff <(echo "$out") tests/expected/$n.out | head -10; fi
done
if [ $linux = 1 ] && command -v addr2line >/dev/null; then
  out=$($ZARK run tests/crash/thunk_names.zk $FLAGS 2>&1); rc=$?
  want="addp at"; [ "$FLAGS" = -O ] && want="main at"
  if [ $rc -ne 1 ]; then fail=$((fail+1)); echo "FAIL crash_thunk_names (exit $rc)"; echo "$out" | tail -10
  elif echo "$out" | grep -qE '\$[zc] at|vb\.' || ! echo "$out" | grep -q "$want"; then fail=$((fail+1)); echo "FAIL crash_thunk_names"; echo "$out" | tail -10
  else pass=$((pass+1)); echo "ok   crash_thunk_names"; fi
fi
for f in tests/errors/*.zk; do
  out=$(timeout 20 $ZARK run "$f" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then fail=$((fail+1)); echo "FAIL $f (expected an error)"; continue; fi
  if [ $rc -eq 124 ]; then fail=$((fail+1)); echo "FAIL $f (timed out)"; continue; fi
  if [ $rc -ne 1 ]; then fail=$((fail+1)); echo "FAIL $f (exit $rc, expected a diagnostic)"; continue; fi
  case "$out" in *"error: error.Signaled"*) fail=$((fail+1)); echo "FAIL $f (the compiler crashed)"; continue ;; esac
  got=$(printf '%s\n' "$out" | awk 'NF{print; exit}' | sed -E 's/^[^:]+:[0-9]+: //')
  want=$(cat "${f%.zk}.err")
  if [ "$got" = "$want" ]; then pass=$((pass+1)); echo "ok   $f (rejected)"
  else fail=$((fail+1)); echo "FAIL $f (diagnostic)"; echo "  want: $want"; echo "  got:  $got"; fi
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
if ZARK=$ZARK tests/cxxbind.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if ZARK=$ZARK tests/asm_encoding.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if ZARK=$ZARK tests/scale.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if ZARK=$ZARK tests/determinism.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if ZARK=$ZARK tests/fmt_idem.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
if ZARK=$ZARK tests/docs.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
