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

names="enums externc consts sysfilter free resolve broken shadow flat cexpr scope oper misc msgs layout value bits anon rec spec methods lifetime"
for name in $names; do
    flags=
    case $name in broken|misc|msgs) flags=-std=c++20 ;; esac
    timeout 20 "$ZARK" cbind "tests/cxxbind/$name.hpp" $flags > "$name.zk" 2> "$name.err" || fail "$name: exit $?: $(cat "$name.err")"
    diff -u <(nohid "tests/cxxbind/$name.out") <(nohid "$name.zk") || fail "$name: output differs"
    diff -u "tests/cxxbind/$name.err" "$name.err" || fail "$name: warnings differ"
    printf 'import "%s.zk";\nvoid main() {}\n' "$name" > "use_$name.zk"
    "$ZARK" ir "use_$name.zk" > /dev/null || fail "$name: bindings do not compile"
done

"$ZARK" cbind tests/cxxbind/layout.hpp --arch aarch64 --os linux > layout.a64.zk 2> /dev/null || fail "layout a64: exit $?"
diff -u <(nohid tests/cxxbind/layout.a64.out) <(nohid layout.a64.zk) || fail "layout a64: output differs"

grep -q "^skipped std::" sysfilter.err && fail "sysfilter: std:: names in warnings"
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

"$ZARK" cbind tests/cxxbind/free.hpp --inline-c free.cpp > /dev/null 2>&1 || fail "free: exit $?"
sed "s|@DIR@|$(realpath "$T")|" tests/cxxbind/free.cpp.out > free.cpp.exp
diff -u <(nohid free.cpp.exp) <(nohid free.cpp) || fail "free: C++ file differs"
for o in -O0 -O2; do
    clang++ -c $o -Wall -Wextra -Werror free.cpp -o free.o || fail "free $o: C++ file does not compile cleanly"
done

cp -r "$R/tests/cxxbind/interop" interop
(cd interop && "$ZARK" cbind free.hpp -o free_b.zk --inline-c free_b.cpp 2> /dev/null) || fail "interop free: cbind exit $?"
for f in "" --llvm -O; do
    out=$(cd interop && "$ZARK" run $f free.zk free.cpp free_b.cpp 2>&1) || fail "interop free $f: $out"
    [ "$out" = "$(cat interop/free.out)" ] || fail "interop free $f: got: $out"
done

(cd interop && "$ZARK" cbind throw.hpp -o throw_b.zk --inline-c throw_b.cpp 2> /dev/null) || fail "throw: cbind exit $?"
grep -q "try {" interop/throw_b.cpp || fail "throw: no try in the shim"
(cd interop && "$ZARK" build throw.zk throw.cpp throw_b.cpp -o ../throw_exe > /dev/null 2>&1) || fail "throw: build failed"
(ulimit -c 0; ./throw_exe > throw.out 2> throw.err) 2> /dev/null
code=$?
[ $code = 134 ] || fail "throw: expected SIGABRT, got exit $code"
[ "$(cat throw.out)" = "2 0" ] || fail "throw: got: $(cat throw.out)"
[ "$(cat throw.err)" = "zark: uncaught C++ exception in t::boom: bad thing" ] || fail "throw: stderr: $(cat throw.err)"
(cd interop && "$ZARK" cbind throw.hpp -fno-exceptions --inline-c ../nothrow.cpp > /dev/null 2>&1) || fail "nothrow: cbind exit $?"
grep -q "try\|catch\|zark_cxx_fail" nothrow.cpp && fail "nothrow: exception handling with -fno-exceptions"
grep -q "static_cast" nothrow.cpp || fail "nothrow: no shims"
clang++ -fno-exceptions -c -Wall -Wextra -Werror nothrow.cpp -o nothrow.o || fail "nothrow: C++ file does not compile"

(cd interop && "$ZARK" cbind throw.hpp -fno-cxx-exceptions --inline-c ../nocxx.cpp > /dev/null 2>&1) || fail "nocxx: cbind exit $?"
grep -q "try\|catch\|zark_cxx_fail" nocxx.cpp && fail "nocxx: exception handling with -fno-cxx-exceptions"
grep -q "static_cast" nocxx.cpp || fail "nocxx: no shims"

printf 'namespace n { int f(int x, const int& y); }\n' > we.hpp
for w in "-Wmissing-prototypes" "-Weverything" "-Wall -Wextra -Wold-style-cast"; do
    "$ZARK" cbind we.hpp -Werror $w --inline-c we.cpp > we.zk 2> we.err || fail "werror $w: exit $?: $(cat we.err)"
    [ -s we.err ] && fail "werror $w: warnings: $(cat we.err)"
    grep -q "n::f" we.zk || fail "werror $w: n::f not bound"
    clang++ -c -Werror $w we.cpp -o we.o || fail "werror $w: C++ file does not compile"
done

(cd interop && "$ZARK" cbind scope.hpp -o scope_b.zk --inline-c scope_b.cpp 2> /dev/null) || fail "interop scope: cbind exit $?"
for f in "" --llvm -O; do
    out=$(cd interop && "$ZARK" run $f scope.zk scope.cpp scope_b.cpp 2>&1) || fail "interop scope $f: $out"
    [ "$out" = "$(cat interop/scope.out)" ] || fail "interop scope $f: got: $out"
done

(cd interop && "$ZARK" cbind value.hpp -o value_b.zk --inline-c value_b.cpp 2> /dev/null) || fail "interop value: cbind exit $?"
grep -E '^extern "C" ((const )?geo::[A-Za-z0-9_]+ zark|.*[(,] *(const )?geo::[A-Za-z0-9_]+ +[a-z_])' interop/value_b.cpp && fail "interop value: a class crosses a shim by value"
grep -E '^extern .*geo_(V|Vec|Priv|NP|TP|Shape|Circle|A16|M1|M2|MM|Bits|An)[^*A-Za-z0-9_]' interop/value_b.zk && fail "interop value: a struct crosses a shim by value"
for f in "" --llvm -O; do
    out=$(cd interop && "$ZARK" run $f value.zk value.cpp value_b.cpp 2>&1) || fail "interop value $f: $out"
    [ "$out" = "$(cat interop/value.out)" ] || fail "interop value $f: got: $out"
done

for f in "" --llvm -O; do
    out=$(cd interop && "$ZARK" run $f lifetime.zk lifetime.cpp 2>&1) || fail "interop lifetime $f: $out"
    [ "$out" = "$(cat interop/lifetime.out)" ] || fail "interop lifetime $f: got: $out"
done

mkdir -p neg
printf 'import "../methods.zk";\n!void main() { const auto a = c_allocator(); auto n = geo_NT::create(a, 1)?; println(n.get().get()); }\n' > neg/leak.zk
if out=$("$ZARK" ir neg/leak.zk 2>&1); then fail "neg leak: expected failure"; fi
case "$out" in *"not consumed on every path"*) ;; *) fail "neg leak: got: $out" ;; esac
printf 'import "../methods.zk";\n!void main() { const auto a = c_allocator(); auto n = geo_NT::create(a, 1)?; const auto p = n.get(); n.deinit(); println(p.get()); }\n' > neg/after_deinit.zk
if out=$("$ZARK" ir neg/after_deinit.zk 2>&1); then fail "neg after_deinit: expected failure"; fi
case "$out" in *"may have moved or freed"*) ;; *) fail "neg after_deinit: got: $out" ;; esac
printf 'import "../methods.zk";\n!void main() { const auto a = c_allocator(); auto n = geo_NT::create(a, 1)?; const auto p = n.release(); println(n.get().get()); _ = p; }\n' > neg/after_release.zk
if out=$("$ZARK" ir neg/after_release.zk 2>&1); then fail "neg after_release: expected failure"; fi
case "$out" in *"used after 'release'"*) ;; *) fail "neg after_release: got: $out" ;; esac

cp -r "$R/tests/cxxbind/interop/imp" imp
for f in "" --llvm -O; do
    out=$(cd imp && "$ZARK" run $f main.zk lib.cpp 2>&1) || fail "import $f: $out"
    [ "$out" = "$(cat imp/main.out)" ] || fail "import $f: got: $out"
done
cached=$(ls imp/.zark-cache/cbind/*.zk)
[ $(echo "$cached" | wc -l) -eq 1 ] || fail "import: expected one cached binding: $cached"
grep -q "missing" "${cached%.zk}.cpp" || fail "import: no shim for the undefined function"
grep -q "try {" "${cached%.zk}.cpp" || fail "import: no try in the shims"
(cd imp && "$ZARK" cbind lib.hpp --inline-c ../same.cpp > ../same.zk 2> /dev/null) || fail "import_same: cbind exit $?"
diff -u same.zk "$cached" || fail "import_same: cbind and import differ"
diff -u same.cpp "${cached%.zk}.cpp" || fail "import_same: C++ files differ"

mkdir -p shim
real=$(command -v clang++)
printf '#!/bin/sh\necho "$*" >> "%s/clang.log"\n[ "$1" = --version ] && [ -n "$FAKE" ] && { echo "clang version $FAKE"; exit 0; }\nexec "%s" "$@"\n' "$T" "$real" > shim/clang++
chmod +x shim/clang++
before=$(ls imp/.zark-cache/cbind)
: > clang.log
out=$(cd imp && PATH="$T/shim:$PATH" "$ZARK" run main.zk lib.cpp 2>&1) || fail "import_cache_hit: $out"
[ "$out" = "$(cat imp/main.out)" ] || fail "import_cache_hit: got: $out"
grep -q -- "--version" clang.log || fail "import_cache_hit: shim not used: $(cat clang.log)"
if grep -q -- "ast-dump" clang.log; then fail "import_cache_hit: parsed again"; fi
[ "$(ls imp/.zark-cache/cbind)" = "$before" ] || fail "import_cache_hit: new cache files: $(ls imp/.zark-cache/cbind)"

: > clang.log
out=$(cd imp && FAKE=99 PATH="$T/shim:$PATH" "$ZARK" run main.zk lib.cpp 2>&1) || fail "import_clang_change: $out"
[ "$out" = "$(cat imp/main.out)" ] || fail "import_clang_change: got: $out"
grep -q -- "ast-dump" clang.log || fail "import_clang_change: stale binding reused"
[ $(ls imp/.zark-cache/cbind/*.zk | wc -l) -eq 2 ] || fail "import_clang_change: expected two cached bindings: $(ls imp/.zark-cache/cbind)"
if command -v python3 >/dev/null; then
    python3 - "$ZARK" zark2 <<'EOF' || fail "import_compiler_change: cannot patch the compiler"
import sys
b = open(sys.argv[1], "rb").read()
old = b'const auto CX_TODO = '
assert b.count(old) == 1, b.count(old)
open(sys.argv[2], "wb").write(b.replace(old, b'const auto CX_TODX = '))
EOF
    chmod +x zark2
    [ "$(uname -s)" = Darwin ] && codesign -f -s - zark2 2> /dev/null
    : > clang.log
    out=$(cd imp && PATH="$T/shim:$PATH" "$T/zark2" run main.zk lib.cpp 2>&1) || fail "import_compiler_change: $out"
    [ "$out" = "$(cat imp/main.out)" ] || fail "import_compiler_change: got: $out"
    grep -q -- "ast-dump" clang.log || fail "import_compiler_change: stale binding reused"
    [ $(ls imp/.zark-cache/cbind/*.zk | wc -l) -eq 3 ] || fail "import_compiler_change: expected three cached bindings: $(ls imp/.zark-cache/cbind)"
else
    echo "skip import_compiler_change: python3 is not installed"
fi

sed 's/magic = 42/magic = 43/' imp/lib.hpp > imp/lib.hpp.new && mv imp/lib.hpp.new imp/lib.hpp
out=$(cd imp && "$ZARK" run main.zk lib.cpp 2>&1) || fail "import_header_edit: $out"
[ "$out" = "5 32 42 43 5" ] || fail "import_header_edit: got: $out"

out=$(cd imp && "$ZARK" run main.zk lib.cpp -std=c11 2>&1) || fail "import_c_std: $out"
[ "$out" = "5 32 42 43 5" ] || fail "import_c_std: got: $out"

printf 'import "lib.hpp" as lib;\ntest "add" { assert(lib::m::add(2, 3) == 5); assert(lib::digits(7) == 1); }\n' > imp/t.zk
out=$(cd imp && "$ZARK" test t.zk lib.cpp 2>&1) || fail "import_test: $out"
case "$out" in *"1 passed, 0 failed"*) ;; *) fail "import_test: got: $out" ;; esac

mkdir -p proj/src proj/inc
cp "$R/tests/cxxbind/interop/imp/lib.hpp" "$R/tests/cxxbind/interop/imp/lib.cpp" proj/inc/
printf '[package]\nname = "cxp"\n\n[build]\nsources = ["inc/lib.cpp"]\ninclude = ["inc"]\nstd = "c++17"\ncflags = ["-fno-exceptions"]\n' > proj/zark.toml
printf 'import "lib.hpp" as lib;\nvoid main() { println("{lib::m::add(1, 2)} {lib::digits(100)} {lib::strict}"); }\n' > proj/src/main.zk
out=$(cd proj && "$ZARK" run 2>&1) || fail "import_manifest: $out"
[ "$out" = "3 3 1" ] || fail "import_manifest: got: $out"
grep -q "try\|zark_cxx_fail" proj/.zark-cache/cbind/*.cpp && fail "import_manifest: exception handling with -fno-exceptions"

mkdir -p hdr
printf 'namespace n { inline int f() { return 7; } }\n' > hdr/cx.h
printf 'import "cx.h";\nvoid main() {}\n' > hdr/bad.zk
if out=$(cd hdr && "$ZARK" run bad.zk 2>&1); then fail "import_h_cxx: expected failure"; fi
case "$out" in *"if this is a C++ header, import it through a .hpp file that includes it"*) ;; *) fail "import_h_cxx: got: $out" ;; esac
printf '#include "cx.h"\n' > hdr/cx.hpp
printf 'import "cx.hpp" as cx;\nvoid main() { println("{cx::n::f()}"); }\n' > hdr/good.zk
out=$(cd hdr && "$ZARK" run good.zk 2>&1) || fail "import_h_wrapper: $out"
[ "$out" = 7 ] || fail "import_h_wrapper: got: $out"

mkdir -p qd/src/lib
printf 'constexpr int cfg = 3;\n' > qd/src/cfg.hpp
printf '#include "cfg.hpp"\ninline int g() { return cfg * 2; }\n' > qd/src/lib/lib.hpp
printf 'import "lib/lib.hpp" as lib;\nvoid main() { println("{lib::g()}"); }\n' > qd/src/main.zk
out=$(cd qd && "$ZARK" run src/main.zk 2>&1) || fail "import_from_dir: $out"
[ "$out" = 6 ] || fail "import_from_dir: got: $out"
mkdir -p qc/src/lib
printf '#define CFG 4\n' > qc/src/cfg.h
printf '#include "cfg.h"\nstatic inline int g(void) { return CFG * 2; }\n' > qc/src/lib/lib.h
printf 'import "lib/lib.h" as lib;\nvoid main() { println("{lib::g()}"); }\n' > qc/src/main.zk
out=$(cd qc && "$ZARK" run src/main.zk 2>&1) || fail "import_from_dir c: $out"
[ "$out" = 8 ] || fail "import_from_dir c: got: $out"

mkdir -p two
printf 'namespace geo { inline int a() { return 1; } }\n' > two/a.hpp
printf 'namespace geo { inline int b() { return 2; } }\n' > two/b.hpp
printf 'import "a.hpp";\nimport "b.hpp";\nvoid main() {}\n' > two/m.zk
if out=$(cd two && "$ZARK" run m.zk 2>&1); then fail "import_two_ns: expected failure"; fi
case "$out" in *"from a header they both include"*) fail "import_two_ns: C message for C++ headers: $out" ;; esac
case "$out" in *"'a.hpp' and 'b.hpp' both declare 'geo'"*"import them with 'as'"*) ;; *) fail "import_two_ns: got: $out" ;; esac

echo "ok   cxxbind ($names)"
