#!/usr/bin/env bash
# `zark ir` is deterministic: twice in a row, and with ZARK_JOBS=1.
cd "$(dirname "$0")/.."
ZARK=${ZARK:-./build/zark}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
for f in examples/showcase/main.zk tests/std/json.zk selfhost/main.zk; do
    "$ZARK" ir "$f" > "$tmp/a" 2>/dev/null || { echo "FAIL determinism: ir $f"; fail=1; continue; }
    "$ZARK" ir "$f" > "$tmp/b" 2>/dev/null || { echo "FAIL determinism: ir $f (second)"; fail=1; continue; }
    ZARK_JOBS=1 "$ZARK" ir "$f" > "$tmp/c" 2>/dev/null || { echo "FAIL determinism: ir $f (jobs=1)"; fail=1; continue; }
    cmp -s "$tmp/a" "$tmp/b" || { echo "FAIL determinism: $f differs between runs"; fail=1; }
    cmp -s "$tmp/a" "$tmp/c" || { echo "FAIL determinism: $f differs with ZARK_JOBS=1"; fail=1; }
done
if [ $fail -eq 0 ]; then echo "ok   determinism"; else echo "FAIL determinism"; fi
exit $fail
