#!/usr/bin/env bash
R=$(cd "$(dirname "$0")/.." && pwd)
ZARK=$(realpath "${ZARK:-$R/build/zark}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL cbind: $*"; exit 1; }
command -v timeout >/dev/null || timeout() { shift; "$@"; }
nohid() { sed -E 's/zark_inl_[0-9a-f]{16}_/zark_inl_H_/g' "$@"; }
cd "$T"
mkdir -p tests
cp -r "$R/tests/cbind" tests/

for name in scalars structs params layout names consts clash shorten unions fnptr flex ambig inline wrapfix; do
    flags=""
    [ "$name" = shorten ] && flags="-fshort-enums"
    timeout 20 "$ZARK" cbind "tests/cbind/$name.h" $flags > "$name.zk" 2> "$name.err" || fail "$name: exit $?: $(cat "$name.err")"
    diff -u <(nohid "tests/cbind/$name.out") <(nohid "$name.zk") || fail "$name: output differs"
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

cat > use_unions2.zk <<'EOF'
import "unions.zk";
void main() {
    auto u = U{};
    *u.as_d() = 2.5;
    setd(&u, 4.0);
    const auto d = *u.as_d();
    *u.as_i() = 41;
    const auto r = pass(u);
    U[3] arr;
    const auto picked = pick(&arr[0], 2) == &arr[2];
    handle_t h;
    *h.as_a() = 9;
    var_t v;
    v.tag = 2;
    *v.v.as_d() = 0.5;
    auto m = make_holder(6);
    const auto bd = mkbind(5);
    println("{d} {*r.as_i()} {picked} {hsum(h)} {vsum(v)} {m.k} {*m.u.as_y()} {m.pq.p} {m.pq.q} {bd.kind} {bd.v.as_p().x} {bd.v.as_p().y}");
    println("{csize(0)} {csize(1)} {csize(2)} {csize(3)} {csize(4)} {csize(5)} {csize(6)} {csize(7)} {csize(8)} {csize(9)} {csize(10)}");
    println("{sizeof(U)} {sizeof(small)} {sizeof(bytes)} {sizeof(holder)} {sizeof(ev)} {sizeof(handle_t)} {sizeof(var_t)} {sizeof(list)} {sizeof(cbu)} {sizeof(part)} {alignof(list)}");
}
EOF
if [ "$(uname -m)" = x86_64 ]; then
    out=$("$ZARK" run use_unions2.zk tests/cbind/unions.c 2>&1) || fail "unions: run: $out"
    [ "$out" = "$(printf '4 42 true 9 2.5 6 3 97 98 5 6 7\n8 2 3 12 16 8 16 32 8 16 8\n8 2 3 12 16 8 16 32 8 16 8')" ] || fail "unions: got: $out"

cat > use_layout2.zk <<'EOF'
import "layout.zk";
void main() {
    bits b;
    b.storage[0] = 0x0000000700000129;
    b.storage[1] = 3;
    ald a;
    a.storage[0] = 65;
    println("{takebits(b)} {takebitsp(&b)} {takeald(a)} {sizeof(usesbits)} {sizeof(bitu)} {sizeof(pkd)}");
}
EOF
    out=$("$ZARK" run use_layout2.zk tests/cbind/layout.c 2>&1) || fail "layout: run: $out"
    [ "$out" = "37151 37151 65 56 8 7" ] || fail "layout: got: $out"

cat > use_fnptr2.zk <<'EOF'
import "fnptr.zk";
i32 thrice(im* m) { return *m.as_i() * 3; }
void main() {
    auto h = mkp();
    im q;
    *q.as_i() = 20;
    const auto p = h.get();
    println("{h.cb(&q)} {p.x} {p.y} {callp(thrice, 5)} {sizeof(hasfp)} {sizeof(okfp)}");
}
EOF
    for f in --native --llvm; do
        out=$("$ZARK" run $f use_fnptr2.zk tests/cbind/fnptr.c 2>&1) || fail "fnptr $f: run: $out"
        [ "$out" = "40 7 8 16 16 16" ] || fail "fnptr $f: got: $out"
    done
fi

cat > use_flex2.zk <<'EOF'
import "flex.zk";
void main() {
    o1 a;
    o1c b;
    const auto fa = (&a.f as *u8 as i64) - (&a as *u8 as i64);
    const auto fb = (&b.f as *u8 as i64) - (&b as *u8 as i64);
    println("{sizeof(f1)} {alignof(f1)} {sizeof(f1b)} {alignof(f1b)} {sizeof(f1c)} {alignof(f1c)} {sizeof(o1)} {alignof(o1)} {sizeof(o1c)} {fa} {fb} {sizeof(f2)}");
}
EOF
out=$("$ZARK" run use_flex2.zk 2>&1) || fail "flex: run: $out"
[ "$out" = "8 8 8 8 8 8 16 8 16 8 8 8" ] || fail "flex: got: $out"

"$ZARK" cbind tests/cbind/inline.h --inline-c inline.c > /dev/null 2>&1 || fail "inline: exit $?"
sed "s|@DIR@|$(realpath "$T")|" tests/cbind/inline.c.out > inline.c.exp
diff -u <(nohid inline.c.exp) <(nohid inline.c) || fail "inline: C file differs"
for o in -O0 -O2; do
    clang -c $o -Wall -Wextra -Wno-unused-function -Wno-deprecated-non-prototype -Werror inline.c -o inline.o || fail "inline $o: C file does not compile cleanly"
done
cat > use_inline2.zk <<'EOF'
import "inline.zk";
i32 neg(i32 x) { return -x; }
void main() {
    pt p;
    p.x = 1;
    p.y = 2;
    pt_move(&p, 3, 4);
    i32[4] arr;
    arr[0] = 1;
    arr[1] = 2;
    arr[2] = 3;
    arr[3] = 4;
    const auto s = "hello".ptr;
    noop();
    println("{add(2, 3)} {half(5.0)} {nextp(&arr[0]) == &arr[1]} {slen(s)} {slen(skip(s, 2))} {next_color(BLUE)} {is_even(4)} {is_even(3)} {mask(255, 4)}");
    println("{p.x} {p.y} {forced(1)} {apply(neg, 5)} {sum4(&arr[0])} {quad(3)} {later(1)} {twice(21)} {sq(5)} {ident(7)}");
}
EOF
out=$("$ZARK" run use_inline2.zk inline.c 2> run.err) || fail "inline: run: $(cat run.err)"
[ "$out" = "$(printf '5 2.5 true 5 3 0 true false 15\n4 6 7 -5 10 12 101 42 25 7')" ] || fail "inline: got: $out"
if [ "$(uname -m)" = x86_64 ]; then
    printf 'import "inline.zk";\nvoid main() { const auto p = pt_make(8, 9); println("{p.x} {p.y}"); }\n' > use_inline3.zk
    for f in --native --llvm; do
        out=$("$ZARK" run $f use_inline3.zk inline.c 2> run.err) || fail "inline $f: run: $(cat run.err)"
        [ "$out" = "8 9" ] || fail "inline $f: got: $out"
    done
fi

"$ZARK" cbind tests/cbind/wrapfix.h --inline-c wrapfix.c > /dev/null 2>&1 || fail "wrapfix: exit $?"
sed "s|@DIR@|$(realpath "$T")|" tests/cbind/wrapfix.c.out > wrapfix.c.exp
diff -u <(nohid wrapfix.c.exp) <(nohid wrapfix.c) || fail "wrapfix: C file differs"
for o in -O0 -O2; do
    clang -c $o -Wall -Wextra -Wno-unused-function -Werror wrapfix.c -o wrapfix.o || fail "wrapfix $o: C file does not compile cleanly"
done
printf 'import "wrapfix.zk";\nvoid main() { const a1 x = 4; println("{foo(x)} {type_(1)} {g(1)} {*cc("ab".ptr)} {vq(2)} {old(3)}"); }\n' > use_wrapfix.zk
out=$("$ZARK" run use_wrapfix.zk wrapfix.c 2> run.err) || fail "wrapfix: run: $(cat run.err)"
[ "$out" = "9 2 3 98 6 30" ] || fail "wrapfix: got: $out"

for h in dupa dupb; do
    "$ZARK" cbind tests/cbind/$h.h --inline-c $h.c > $h.zk 2> /dev/null || fail "$h: exit $?"
done
printf 'import "dupa.zk" as a;\nimport "dupb.zk" as b;\nvoid main() { println("{a::dup(1)} {b::dup(2)} {b::dupb(3)}"); }\n' > use_dup.zk
out=$("$ZARK" run use_dup.zk dupa.c dupb.c 2> run.err) || fail "dup: run: $(cat run.err)"
[ "$out" = "2 3 8" ] || fail "dup: got: $out"

mkdir -p sysinc
printf 'struct inner { int a; };\n#define INNER 1\nint unused_inner(void);\n' > sysinc/inner.h
printf '#include <inner.h>\nint top(struct inner* p);\n' > sysinc/top.h
out=$("$ZARK" cbind top.h -isystem sysinc 2>&1) || fail "system dir: exit $?: $out"
[ "$out" = "$(printf 'struct inner { i32 a; }\nextern i32 top(inner* p);')" ] || fail "system dir: got: $out"

out=$("$ZARK" cbind flag.h -D VAL=3 2>&1) || fail "flags with a space: exit $?: $out"
mkdir -p spc
printf '#define SV 5\n' > spc/sv.h
printf 'import "sv.h";\nvoid main() { println("{SV}"); }\n' > use_sv.zk
out=$("$ZARK" run use_sv.zk -isystem spc 2>&1) || fail "import_isystem_pair: $out"
[ "$out" = 5 ] || fail "import_isystem_pair: got: $out"
out=$("$ZARK" run use_sv.zk -I spc 2>&1) || fail "import_I_space: $out"
[ "$out" = 5 ] || fail "import_I_space: got: $out"
out=$("$ZARK" cbind sv.h -I spc 2>&1) || fail "cbind -I space: exit $?: $out"

printf '#include <stdio.h>\nint put(FILE* f);\n' > file.h
"$ZARK" cbind file.h > file.zk 2> /dev/null || fail "FILE: exit $?"
printf 'import "file.zk";\nvoid main() { const auto n = put(null); }\n' > use_file.zk
"$ZARK" ir use_file.zk > /dev/null || fail "FILE: pointer type does not resolve"

for i in $(seq 1 20000); do
    if [ "$i" = 1 ]; then echo "#define M1 1"; else echo "#define M$i M$((i - 1))"; fi
done > chain.h
timeout 10 "$ZARK" cbind chain.h > chain.zk 2> chain.err || fail "chain: exit $?"
grep -qx "const auto M50 = 1;" chain.zk || fail "chain: M50 missing"
grep -qx "skipped M20000: expansion too deep" chain.err || fail "chain: M20000 not skipped: $(tail -1 chain.err)"

printf 'struct E {};\nstruct H { struct E a[1000000000]; };\nint f(struct H h);\n' > empty.h
timeout 5 "$ZARK" cbind empty.h > empty.zk 2>&1 || fail "empty array: exit $?"
grep -qx "extern i32 f(H h);" empty.zk || fail "empty array: f missing"

cp -r "$R/tests/cbind/interop" interop
for f in "" --llvm -O; do
    out=$(cd interop && "$ZARK" run $f main.zk lib.c -I. 2>&1) || fail "import_basic $f: $out"
    [ "$out" = "$(cat interop/main.out)" ] || fail "import_basic $f: got: $out"
done
if [ "$(uname -m)" = x86_64 ]; then
    for f in "" --llvm -O; do
        out=$(cd interop && "$ZARK" run $f byval.zk lib.c -I. 2>&1) || fail "import_byval $f: $out"
        [ "$out" = "3 1.5 4.5" ] || fail "import_byval $f: got: $out"
    done
fi

(cd interop && "$ZARK" cbind lib.h -I. --inline-c ../same.c > ../same.zk 2> /dev/null) || fail "import_same: cbind exit $?"
cached=$(grep -l "lib_magic" interop/.zark-cache/cbind/*.zk)
[ $(echo "$cached" | wc -l) -eq 1 ] || fail "import_same: expected one cached binding, got: $cached"
diff -u same.zk "$cached" || fail "import_same: cbind and import differ"
diff -u same.c "${cached%.zk}.c" || fail "import_same: inline C files differ"

(cd interop && "$ZARK" ir main.zk -I. > /dev/null) || fail "import_ir: zark ir failed"
printf 'import "lib.h" as lib;\ntest "magic" { assert(lib::lib_magic() == 42); assert(lib::scaled(1) == 42); }\n' > interop/t.zk
out=$(cd interop && "$ZARK" test t.zk lib.c -I. 2>&1) || fail "import_test: $out"
case "$out" in *"1 passed, 0 failed"*) ;; *) fail "import_test: got: $out" ;; esac

mkdir -p shim
real=$(command -v clang)
printf '#!/bin/sh\necho "$*" >> "%s/clang.log"\nexec "%s" "$@"\n' "$T" "$real" > shim/clang
chmod +x shim/clang
cp -r "$R/tests/cbind/interop" hit
(cd hit && PATH="$T/shim:$PATH" "$ZARK" run main.zk lib.c > /dev/null 2>&1) || fail "import_cache_hit: first run"
grep -q -- "-E" clang.log || fail "import_cache_hit: shim not used: $(cat clang.log)"
: > clang.log
out=$(cd hit && PATH="$T/shim:$PATH" "$ZARK" run main.zk lib.c 2>&1) || fail "import_cache_hit: second run: $out"
[ "$out" = "$(cat interop/main.out)" ] || fail "import_cache_hit: got: $out"
if grep -E -- "(^| )-E( |$)|fdump-record-layouts" clang.log; then fail "import_cache_hit: preprocessed again"; fi

sed 's/#define LIB_MAGIC 42/#define LIB_MAGIC 43/' hit/lib.h > hit/lib.h.new && mv hit/lib.h.new hit/lib.h
out=$(cd hit && "$ZARK" run main.zk lib.c 2>&1) || fail "import_header_edit: $out"
[ "$(echo "$out" | head -1)" = "43 interop 43 86" ] || fail "import_header_edit: got: $out"

mkdir -p "tw/my lib" tw/app/sub
cp interop/lib.h interop/lib.c "tw/my lib/"
printf 'import "../../my lib/lib.h";\ni32 from_sub() { return lib_magic() + 1; }\n' > tw/app/sub/plain.zk
printf 'import "lib.h" as other;\ni32 from_other() { return other::scaled(1); }\n' > tw/app/sub/other.zk
printf 'import "sub/plain.zk";\nimport "lib.h" as lib;\nimport "sub/other.zk";\nimport "lib.h" as again;\nvoid main() { println("{from_sub()} {from_other()} {lib::LIB_MAGIC} {again::sum_ints(2, 1, 2)} {LIB_NAME}"); }\n' > tw/app/main.zk
for f in "" --llvm; do
    out=$(cd tw/app && "$ZARK" run $f main.zk "../my lib/lib.c" "-I../my lib" 2>&1) || fail "import_twice $f: $out"
    [ "$out" = "43 42 42 3 interop" ] || fail "import_twice $f: got: $out"
done
[ $(ls tw/app/.zark-cache/cbind/*.zk | wc -l) -eq 1 ] || fail "import_twice: expected one cached binding: $(ls tw/app/.zark-cache/cbind)"
[ $(ls tw/app/.zark-cache/cbind/*.c | wc -l) -eq 1 ] || fail "import_twice: expected one inline C file: $(ls tw/app/.zark-cache/cbind)"

printf 'import "lib.h" as lib;\nimport "sub/plain.zk";\nvoid main() { println("{lib::LIB_MAGIC}"); }\n' > tw/app/bad.zk
if out=$(cd tw/app && "$ZARK" run bad.zk "../my lib/lib.c" "-I../my lib" 2>&1); then fail "import_alias_plain: expected failure"; fi
case "$out" in *"error: '../../my lib/lib.h' is imported as 'lib' elsewhere"*'import "../../my lib/lib.h" as lib;'*) ;; *) fail "import_alias_plain: got: $out" ;; esac

printf 'int f(void);\n' > cpp.hpp
printf 'import "cpp.hpp";\nvoid main() {}\n' > use_cpp.zk
out=$("$ZARK" run use_cpp.zk 2>&1); code=$?
[ $code = 1 ] || fail "import_cpp_header: exit $code: $out"
[ "$out" = "error: C++ headers are not supported yet: cpp.hpp" ] || fail "import_cpp_header: got: $out"

mkdir -p "inc dir"
printf 'import "nosuch.h";\nvoid main() {}\n' > use_missing.zk
out=$("$ZARK" run use_missing.zk "-Iinc dir" 2>&1); code=$?
[ $code = 1 ] || fail "import_missing: exit $code: $out"
case "$out" in *"error: cannot find C header 'nosuch.h'; searched: ., inc dir, "*/usr/include*) ;; *) fail "import_missing: got: $out" ;; esac

mkdir -p mf/src mf/inc
printf '#ifdef FEATURE\nint feature(void);\n#endif\n#if __STDC_VERSION__ == 201112L\n#define STDV 11\n#endif\n#define CFV CF\n' > mf/inc/feat.h
printf '#include "feat.h"\nint feature(void) { return 5; }\n' > mf/inc/feat.c
printf '[package]\nname = "mf"\n\n[build]\nsources = ["inc/feat.c"]\ninclude = ["inc"]\ndefines = ["FEATURE"]\nstd = "c11"\ncflags = ["-DCF=2"]\n' > mf/zark.toml
printf 'import "feat.h" as f;\nvoid main() { println("{f::feature()} {f::STDV} {f::CFV}"); }\n' > mf/src/main.zk
out=$(cd mf && "$ZARK" run 2>&1) || fail "import_manifest: $out"
[ "$out" = "5 11 2" ] || fail "import_manifest: got: $out"
out=$("$ZARK" run mf/src/main.zk 2>&1) || fail "import_manifest explicit file: $out"
[ "$out" = "5 11 2" ] || fail "import_manifest explicit file: got: $out"
if command -v python3 >/dev/null; then
    out=$(python3 "$R/tests/cbind/lsp.py" "$ZARK" "$T/mf/src/main.zk" "$T") || fail "lsp_manifest_flags: $out"
    [ -z "$out" ] || fail "lsp_manifest_flags: false diagnostics: $out"
    printf 'import "feat.h" as f;\nvoid main() { nope(); }\n' > mf/src/bad.zk
    out=$(python3 "$R/tests/cbind/lsp.py" "$ZARK" "$T/mf/src/bad.zk" "$T") || fail "lsp_manifest_flags bad: $out"
    case "$out" in *nope*) ;; *) fail "lsp_manifest_flags: no diagnostic for nope(): $out" ;; esac
else
    echo "skip lsp_manifest_flags: python3 is not installed"
fi
sed 's/defines = \["FEATURE"\]/defines = []/' mf/zark.toml > mf/zark.toml.new && mv mf/zark.toml.new mf/zark.toml
if out=$(cd mf && "$ZARK" run 2>&1); then fail "import_manifest: feature still bound without FEATURE"; fi

{
    printf 'import "lib.h" as lib;\nvoid main() {\n'
    for n in $(sed -n 's/^struct \([A-Za-z_0-9]*\) .*/\1/p' same.zk); do printf '    println("{sizeof(lib::%s)}");\n' "$n"; done
    printf '}\n'
} > interop/sizes.zk
{
    printf '#include <stdio.h>\n#include "lib.h"\nint main(void) {\n'
    for n in $(sed -n 's/^struct \([A-Za-z_0-9]*\) .*/\1/p' same.zk); do
        kind=struct
        grep -q "union $n " interop/lib.h && kind=union
        printf '    printf("%%zu\\n", sizeof(%s %s));\n' "$kind" "$n"
    done
    printf '    return 0;\n}\n'
} > interop/sizes.c
[ "$(grep -c sizeof interop/sizes.c)" -ge 3 ] || fail "sizeof_matches: too few structs"
clang interop/sizes.c -o sizes_c || fail "sizeof_matches: C program"
out=$(cd interop && "$ZARK" run sizes.zk 2>&1) || fail "sizeof_matches: $out"
[ "$out" = "$(./sizes_c)" ] || fail "sizeof_matches: zark $out vs C $(./sizes_c)"
cp -r "$R/tests/cbind/interop" cor
(cd cor && "$ZARK" run main.zk lib.c > /dev/null 2>&1) || fail "import_corrupt: first run"
zk=$(ls cor/.zark-cache/cbind/*.zk)
for damage in "cut $zk" "empty $zk" "copy $zk" "remove ${zk%.zk}.c" "empty ${zk%.zk}.c" "copy ${zk%.zk}.c"; do
    set -- $damage
    case "$1" in
        cut) head -c 100 "$2" > "$2.t" && mv "$2.t" "$2" ;;
        empty) : > "$2" ;;
        copy) cp cor/lib.c "$2" ;;
        remove) rm "$2" ;;
    esac
    out=$(cd cor && "$ZARK" run main.zk lib.c 2>&1) || fail "import_corrupt ($damage): $out"
    [ "$out" = "$(cat interop/main.out)" ] || fail "import_corrupt ($damage): got: $out"
done

mkdir -p sh/inc2 sh/d sh/q
printf '#include <dep.h>\n' > sh/d/a.h
printf '#define DEPV 1\n' > sh/inc2/dep.h
printf 'import "d/a.h";\nvoid main() { println("{DEPV}"); }\n' > sh/m.zk
out=$(cd sh && "$ZARK" run m.zk -Iinc1 -Iinc2 2>&1) || fail "import_shadow: $out"
[ "$out" = 1 ] || fail "import_shadow: got: $out"
mkdir -p sh/inc1
printf '#define DEPV 77\n' > sh/inc1/dep.h
out=$(cd sh && "$ZARK" run m.zk -Iinc1 -Iinc2 2>&1) || fail "import_shadow -I: $out"
[ "$out" = 77 ] || fail "import_shadow -I: stale binding: $out"
printf '#include "x.h"\n' > sh/q/b.h
printf '#define XV 1\n' > sh/inc2/x.h
printf 'import "q/b.h";\nvoid main() { println("{XV}"); }\n' > sh/n.zk
out=$(cd sh && "$ZARK" run n.zk -Iinc2 2>&1) || fail "import_shadow quote: $out"
[ "$out" = 1 ] || fail "import_shadow quote: got: $out"
printf '#define XV 5\n' > sh/q/x.h
out=$(cd sh && "$ZARK" run n.zk -Iinc2 2>&1) || fail "import_shadow quote: $out"
[ "$out" = 5 ] || fail "import_shadow quote: stale binding: $out"

mkdir -p shared
printf 'struct cm { int v; };\n' > shared/common.h
printf '#include "common.h"\nint fa(void);\n' > shared/a.h
printf '#include "common.h"\nint fb(void);\n' > shared/b.h
printf 'import "a.h";\nimport "b.h";\nvoid main() {}\n' > shared/m.zk
if out=$(cd shared && "$ZARK" run m.zk 2>&1); then fail "import_shared: expected failure"; fi
case "$out" in *"'a.h' and 'b.h' both declare 'cm'"*) ;; *) fail "import_shared: got: $out" ;; esac
case "$out" in *zark-cache*) fail "import_shared: names the cache: $out" ;; esac

mkdir -p vend/d1 vend/d2
printf 'static inline int tw(int x) { return x * 2; }\n' | tee vend/d1/v.h > vend/d2/v.h
printf 'import "d1/v.h" as p;\nimport "d2/v.h" as q;\nvoid main() { println("{p::tw(1) + q::tw(2)}"); }\n' > vend/m.zk
out=$(cd vend && "$ZARK" run m.zk 2>&1) || fail "import_vendored: $out"
[ "$out" = 6 ] || fail "import_vendored: got: $out"

printf 'import "stdio.h";\nvoid main() {}\n' > use_stdio.zk
if out=$("$ZARK" run use_stdio.zk -std=bogus 2>&1); then fail "import_bad_flag: expected failure"; fi
case "$out" in *bogus*) ;; *) fail "import_bad_flag: no clang error: $out" ;; esac
case "$out" in *"cannot find"*) fail "import_bad_flag: claims missing: $out" ;; esac
printf 'import "/nonexistent/x.h";\nvoid main() {}\n' > use_abs.zk
if out=$("$ZARK" run use_abs.zk 2>&1); then fail "import_abs_missing: expected failure"; fi
case "$out" in *"error: cannot find C header '/nonexistent/x.h'"*) ;; *) fail "import_abs_missing: got: $out" ;; esac
case "$out" in *searched*) fail "import_abs_missing: lists search dirs: $out" ;; esac

if [ "$(id -u)" != 0 ]; then
    mkdir -p unr
    printf 'int un(void);\n' > unr/un.h
    printf 'import "un.h";\nvoid main() {}\n' > unr/m.zk
    (cd unr && "$ZARK" build m.zk -o m > /dev/null 2>&1) || fail "import_unreadable: first run"
    chmod 000 unr/un.h
    if out=$(cd unr && "$ZARK" build m.zk -o m 2>&1); then fail "import_unreadable: expected failure"; fi
    chmod 644 unr/un.h
    case "$out" in *"un.h"*"Permission denied"*) ;; *) fail "import_unreadable: got: $out" ;; esac
fi
echo "ok   cbind"
