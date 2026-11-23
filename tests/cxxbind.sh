#!/usr/bin/env bash
R=$(cd "$(dirname "$0")/.." && pwd)
ZARK=$(realpath "${ZARK:-$R/build/zark}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL cxxbind: $*"; exit 1; }
command -v timeout >/dev/null || timeout() { shift; "$@"; }
nohid() { sed -E -e 's/zark_(cxx|inl|var|bf)_[0-9a-f]{16}_/zark_\1_H_/g' -e 's/ZARK_USE_[0-9a-f]{16}_/ZARK_USE_H_/g' "$@"; }
cd "$T"
mkdir -p tests
cp -r "$R/tests/cxxbind" tests/

names="enums externc consts sysfilter"
for name in $names; do
    timeout 20 "$ZARK" cbind "tests/cxxbind/$name.hpp" > "$name.zk" 2> "$name.err" || fail "$name: exit $?: $(cat "$name.err")"
    diff -u <(nohid "tests/cxxbind/$name.out") <(nohid "$name.zk") || fail "$name: output differs"
    diff -u "tests/cxxbind/$name.err" "$name.err" || fail "$name: warnings differ"
    printf 'import "%s.zk";\nvoid main() {}\n' "$name" > "use_$name.zk"
    "$ZARK" ir "use_$name.zk" > /dev/null || fail "$name: bindings do not compile"
done

grep -q "std::" sysfilter.err && fail "sysfilter: std:: names in warnings"
[ "$(wc -l < sysfilter.zk)" -le 10 ] || fail "sysfilter: output is not small"

printf '#if VAL != 3\n#error no\n#endif\nextern "C" int v(void);\n' > flag.hpp
out=$("$ZARK" cbind flag.hpp -DVAL=3 2>&1) || fail "flags: exit $?: $out"
[ "$out" = "extern i32 v();" ] || fail "flags: got: $out"

printf 'extern "C" char pick(char c);\n' > chars.hpp
out=$("$ZARK" cbind chars.hpp -fsigned-char 2>&1) || fail "signed char: exit $?: $out"
[ "$out" = "extern i8 pick(i8 c);" ] || fail "signed char: got: $out"
out=$("$ZARK" cbind chars.hpp -funsigned-char 2>&1) || fail "unsigned char: exit $?: $out"
[ "$out" = "extern u8 pick(u8 c);" ] || fail "unsigned char: got: $out"

if "$ZARK" cbind nosuch.hpp > /dev/null 2> err.txt; then fail "missing header: expected failure"; fi
grep -q "nosuch.hpp" err.txt || fail "missing header: clang message not shown: $(cat err.txt)"

printf 'import "consts.zk";\nimport "enums.zk";\nvoid main() { println("{cfg_Twice} {Wide} {Pi} {On} {Kind_Tri} {geo_Dir_Left} {Huge} {sizeof(geo_Dir)} {sizeof(Big)}"); }\n' > use_vals.zk
out=$("$ZARK" run use_vals.zk 2>&1) || fail "values: run: $out"
[ "$out" = "6 -5000000000 3.5 true 7 -1 18446744073709551615 1 8" ] || fail "values: got: $out"

echo "ok   cxxbind ($names)"
