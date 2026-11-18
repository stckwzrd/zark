#!/usr/bin/env bash
# Runs all examples and compares against expected output.
cd "$(dirname "$0")/.."
VIBE=${VIBE:-./zig-out/bin/vibe}; [ -x "$VIBE" ] || VIBE=./vibe
pass=0; fail=0
check() { # name, cmd...
  local name=$1; shift
  if diff -u "tests/expected/$name.out" <("$@" 2>&1) >/dev/null; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name"; diff -u "tests/expected/$name.out" <("$@" 2>&1) | head -20; fi
}
for n in hello features edge memory funcs unions minilang stdlib2 io; do check $n $VIBE run examples/$n.vibe $FLAGS; done
check interop $VIBE run examples/interop/main.vibe examples/interop/mathlib.c examples/interop/engine.cpp $FLAGS
for f in tests/errors/*.vibe; do
  if $VIBE run "$f" >/dev/null 2>&1; then fail=$((fail+1)); echo "FAIL $f (expected an error)"; else pass=$((pass+1)); echo "ok   $f (rejected)"; fi
done
# self-hosted compiler: its lexer must match the Zig reference token for token
REF=./zig-out/bin/vibe
FILES="src/std.vibe $(ls selfhost/*.vibe examples/*.vibe examples/interop/*.vibe tests/errors/*.vibe)"
if [ -x "$REF" ]; then
  if cmp -s <($VIBE tokens $FILES) <($REF tokens $FILES); then pass=$((pass+1)); echo "ok   tokens == zig reference ($($REF tokens $FILES | wc -l) tokens)"
  else fail=$((fail+1)); echo "FAIL tokens differ from zig reference"; fi
fi
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
