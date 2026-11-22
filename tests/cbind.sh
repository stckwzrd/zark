#!/usr/bin/env bash
R=$(cd "$(dirname "$0")/.." && pwd)
ZARK=$(realpath "${ZARK:-$R/build/zark}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL cbind: $*"; exit 1; }
cd "$T"
mkdir -p tests
cp -r "$R/tests/cbind" tests/

for name in scalars structs; do
    "$ZARK" cbind "tests/cbind/$name.h" > "$name.zk" 2> "$name.err" || fail "$name: exit $?: $(cat "$name.err")"
    diff -u "tests/cbind/$name.out" "$name.zk" || fail "$name: output differs"
    diff -u "tests/cbind/$name.err" "$name.err" || fail "$name: warnings differ"
    printf 'import "%s.zk";\nvoid main() {}\n' "$name" > "use_$name.zk"
    "$ZARK" ir "use_$name.zk" > /dev/null || fail "$name: bindings do not compile"
done

"$ZARK" cbind tests/cbind/structs.h -o out.zk 2> /dev/null || fail "-o: exit $?"
diff -u tests/cbind/structs.out out.zk || fail "-o: output differs"

printf '#if VAL != 3\n#error no\n#endif\nint v(void);\n' > flag.h
out=$("$ZARK" cbind flag.h -DVAL=3 2>&1) || fail "flags: exit $?: $out"
[ "$out" = "extern i32 v();" ] || fail "flags: got: $out"

if "$ZARK" cbind nosuch.h > /dev/null 2> err.txt; then fail "missing header: expected failure"; fi
grep -q "nosuch.h" err.txt || fail "missing header: clang message not shown: $(cat err.txt)"
echo "ok   cbind"
