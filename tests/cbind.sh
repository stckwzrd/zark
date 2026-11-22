#!/usr/bin/env bash
R=$(cd "$(dirname "$0")/.." && pwd)
ZARK=$(realpath "${ZARK:-$R/build/zark}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL cbind: $*"; exit 1; }
cd "$T"
mkdir -p tests
cp -r "$R/tests/cbind" tests/

for name in scalars structs params layout names consts clash shorten; do
    flags=""
    [ "$name" = shorten ] && flags="-fshort-enums"
    timeout 20 "$ZARK" cbind "tests/cbind/$name.h" $flags > "$name.zk" 2> "$name.err" || fail "$name: exit $?: $(cat "$name.err")"
    diff -u "tests/cbind/$name.out" "$name.zk" || fail "$name: output differs"
    diff -u "tests/cbind/$name.err" "$name.err" || fail "$name: warnings differ"
    printf 'import "%s.zk";\nvoid main() {}\n' "$name" > "use_$name.zk"
    "$ZARK" ir "use_$name.zk" > /dev/null || fail "$name: bindings do not compile"
done

printf 'import "params.zk";\ni32 inc(i32 x) { return x; }\nvoid set(cbs* c, vec3 v) { c.cb = inc; usev(&v[0]); }\nvoid main() { set(null, [1.0, 2.0, 3.0]); }\n' > call_params.zk
"$ZARK" ir call_params.zk > call.ll || fail "params: typed use does not compile"
grep -q "declare void @usev(ptr)" call.ll || fail "params: usev does not take a pointer"

"$ZARK" cbind tests/cbind/structs.h -o out.zk 2> /dev/null || fail "-o: exit $?"
diff -u tests/cbind/structs.out out.zk || fail "-o: output differs"

printf '#if VAL != 3\n#error no\n#endif\nint v(void);\n' > flag.h
out=$("$ZARK" cbind flag.h -DVAL=3 2>&1) || fail "flags: exit $?: $out"
[ "$out" = "extern i32 v();" ] || fail "flags: got: $out"

if "$ZARK" cbind nosuch.h > /dev/null 2> err.txt; then fail "missing header: expected failure"; fi
grep -q "nosuch.h" err.txt || fail "missing header: clang message not shown: $(cat err.txt)"

printf 'import "consts.zk";\nvoid main() { println("{H1} {ALLONES} {TEXTP.len} {NEGF} {X1} {S2} {NAME}"); }\n' > use_consts2.zk
out=$("$ZARK" run use_consts2.zk 2>&1) || fail "consts: run: $out"
[ "$out" = "18446744073709551615 18446744073709551615 6 -1.5 -2147483648 -1 text" ] || fail "consts: got: $out"

printf '%s\n' "enum { HI = '\\377' };" "#define HC '\\377'" > chars.h
out=$("$ZARK" cbind chars.h -fsigned-char 2>&1) || fail "signed char: exit $?: $out"
[ "$out" = "$(printf 'const auto HI = -1;\nconst auto HC = -1;')" ] || fail "signed char: got: $out"
out=$("$ZARK" cbind chars.h -funsigned-char 2>&1) || fail "unsigned char: exit $?: $out"
[ "$out" = "$(printf 'const auto HI = 255;\nconst auto HC = 255;')" ] || fail "unsigned char: got: $out"

mkdir -p sysd
printf '#undef KEEP\n#define SYSM 1\n' > sysd/s.h
printf '#define KEEP 1\n#include <s.h>\n#define USE_SYSM (SYSM + 1)\n' > undef.h
out=$("$ZARK" cbind undef.h -isystem sysd 2>&1) || fail "system undef: exit $?: $out"
[ "$out" = "$(printf 'skipped KEEP: undefined in system header\nconst auto USE_SYSM = 2;')" ] || fail "system undef: got: $out"
printf '#define A "abc\n#define B "ok"\n' > unterm.h
out=$("$ZARK" cbind unterm.h 2>&1) || fail "unterminated string: exit $?: $out"
[ "$out" = "$(printf 'skipped A: not a constant\nconst auto B = "ok";')" ] || fail "unterminated string: got: $out"

for i in $(seq 1 20000); do
    if [ "$i" = 1 ]; then echo "#define M1 1"; else echo "#define M$i M$((i - 1))"; fi
done > chain.h
timeout 10 "$ZARK" cbind chain.h > chain.zk 2> chain.err || fail "chain: exit $?"
grep -qx "const auto M50 = 1;" chain.zk || fail "chain: M50 missing"
grep -qx "skipped M20000: expansion too deep" chain.err || fail "chain: M20000 not skipped: $(tail -1 chain.err)"
echo "ok   cbind"
