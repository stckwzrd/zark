#!/usr/bin/env bash
R=$(cd "$(dirname "$0")/.." && pwd)
ZARK=$(realpath "${ZARK:-$R/build/zark}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL cbind: $*"; exit 1; }
cd "$T"
mkdir -p tests
cp -r "$R/tests/cbind" tests/

for name in scalars structs params layout names consts clash shorten unions fnptr flex ambig inline; do
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
diff -u inline.c.exp inline.c || fail "inline: C file differs"
clang -c -Wall -Wextra -Wno-unused-function -Wno-deprecated-non-prototype -Werror inline.c -o inline.o || fail "inline: C file does not compile cleanly"
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
    println("{p.x} {p.y} {forced(1)} {apply(neg, 5)} {sum4(&arr[0])} {quad(3)} {match_(3)} {later(1)} {twice(21)} {sq(5)} {ident(7)}");
}
EOF
out=$("$ZARK" run use_inline2.zk inline.c 2> run.err) || fail "inline: run: $(cat run.err)"
[ "$out" = "$(printf '5 2.5 true 5 3 0 true false 15\n4 6 7 -5 10 12 -3 101 42 25 7')" ] || fail "inline: got: $out"
if [ "$(uname -m)" = x86_64 ]; then
    printf 'import "inline.zk";\nvoid main() { const auto p = pt_make(8, 9); println("{p.x} {p.y}"); }\n' > use_inline3.zk
    for f in --native --llvm; do
        out=$("$ZARK" run $f use_inline3.zk inline.c 2> run.err) || fail "inline $f: run: $(cat run.err)"
        [ "$out" = "8 9" ] || fail "inline $f: got: $out"
    done
fi

mkdir -p sysinc
printf 'struct inner { int a; };\n#define INNER 1\nint unused_inner(void);\n' > sysinc/inner.h
printf '#include <inner.h>\nint top(struct inner* p);\n' > sysinc/top.h
out=$("$ZARK" cbind top.h -isystem sysinc 2>&1) || fail "system dir: exit $?: $out"
[ "$out" = "$(printf 'struct inner { i32 a; }\nextern i32 top(inner* p);')" ] || fail "system dir: got: $out"

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
echo "ok   cbind"
