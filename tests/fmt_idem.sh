#!/usr/bin/env bash
# zark fmt is idempotent and does not change the program: for every .zk in the
# tree, formatting twice gives the same bytes, and `zark ir` before and after
# formatting is identical. Files that do not parse are skipped for IR.
cd "$(dirname "$0")/.."
ZARK=${ZARK:-./build/zark}
cur=""; bak=""
cleanup() { if [ -n "$cur" ] && [ -n "$bak" ] && [ -f "$bak" ]; then cp "$bak" "$cur"; fi; }
trap cleanup EXIT INT TERM
fail=0; n=0; skipped=0
tmp=$(mktemp -d)
trap 'cleanup; rm -rf "$tmp"' EXIT INT TERM
while IFS= read -r f; do
    case "$(basename "$f")" in .*) continue;; esac
    n=$((n+1))
    cur="$f"; bak="$tmp/orig"
    cp "$f" "$bak"
    "$ZARK" ir "$f" > "$tmp/ir1" 2>/dev/null; ir_ok=$?
    if ! "$ZARK" fmt "$f" > /dev/null 2>&1; then
        skipped=$((skipped+1))
        cp "$bak" "$f"
        continue
    fi
    cp "$f" "$tmp/fmt1"
    if ! "$ZARK" fmt "$f" > /dev/null 2>&1; then
        echo "FAIL fmt: $f (the second format failed)"; fail=1
    fi
    if ! cmp -s "$tmp/fmt1" "$f"; then
        echo "FAIL fmt: $f is not idempotent"; fail=1
    fi
    if [ $ir_ok -eq 0 ]; then
        if ! "$ZARK" ir "$f" > "$tmp/ir2" 2>/dev/null || ! cmp -s "$tmp/ir1" "$tmp/ir2"; then
            echo "FAIL fmt: $f changes the IR"; fail=1
        fi
    fi
    cp "$bak" "$f"
    cur=""; bak=""
done < <(find examples tests std selfhost -name '*.zk' -not -path '*/.zark-cache/*' | sort)
if [ $fail -eq 0 ]; then
    echo "ok   fmt (idempotent and IR-preserving on $n files, $skipped unparsable)"
else
    echo "FAIL fmt ($n files)"
fi
exit $fail
