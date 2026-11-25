#!/usr/bin/env bash
R=$(cd "$(dirname "$0")/.." && pwd)
. "$R/tests/compiler.sh"
ZARK=$(realpath "${ZARK:-./build/zark}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL cbuild: $*"; exit 1; }
cd "$T"

mkdir -p "a b/inc"
printf '#include "cfg.h"\nlong answer(void) { return ANSWER; }\n' > "a b/ans.c"
printf '#define BASE 40\n' > "a b/inc/cfg.h"
cat > main.zk <<'ZK'
extern i64 answer();
i32 main() {
    println("{answer()}");
    return 0;
}
ZK

out=$("$ZARK" run main.zk "a b/ans.c" "-Ia b/inc" -DANSWER=42 2>&1)
[ "$out" = "42" ] || fail "flags_cli: expected 42, got: $out"
out=$("$ZARK" run main.zk "a b/ans.c" "-Ia b/inc" -DANSWER=BASE+2 2>&1)
[ "$out" = "42" ] || fail "flags_cli macro: expected 42, got: $out"
mkdir -p mf/src "mf/inc dir" mf/c
printf '[package]\nname = "mf"\n\n[build]\nsources = ["c/s.cpp"]\ninclude = ["inc dir"]\ndefines = ["N=3"]\nstd = "c++17"\ncflags = ["-DM=5"]\n' > mf/zark.toml
printf '#define BASE 10\n' > "mf/inc dir/val.h"
printf '#include <string_view>\n#include "val.h"\nextern "C" long cxx_len() { std::string_view s("hello"); return s.size() + N + M + BASE; }\n' > mf/c/s.cpp
printf 'extern i64 cxx_len();\nvoid main() { println("{cxx_len()}"); }\n' > mf/src/main.zk
out=$(cd mf && "$ZARK" run 2>&1)
[ "$out" = "23" ] || fail "manifest_fields: expected 23, got: $out"
out=$("$ZARK" run mf/src/main.zk 2>&1)
[ "$out" = "23" ] || fail "manifest_fields explicit file: expected 23, got: $out"

mkdir -p df/src dep/src dep/c
printf '[package]\nname = "dep"\n\n[build]\nsources = ["c/d.c"]\ndefines = ["DEP_VAL=7"]\n' > dep/zark.toml
printf 'long dep_val(void) { return DEP_VAL; }\n' > dep/c/d.c
printf 'i64 unused() { return 0; }\n' > dep/src/lib.zk
printf '[package]\nname = "df"\n\n[dependencies]\ndep = { path = "../dep" }\n' > df/zark.toml
printf 'extern i64 dep_val();\nvoid main() { println("{dep_val()}"); }\n' > df/src/main.zk
out=$(cd df && "$ZARK" run 2>&1)
[ "$out" = "7" ] || fail "dependency_flags: expected 7, got: $out"

mkdir -p mix
printf '_Static_assert(1, "c11");\nlong c_val(void) { return 1; }\n' > mix/a.c
printf '#include <string_view>\nextern "C" long cxx_val() { std::string_view s("ab"); return s.size(); }\n' > mix/b.cpp
printf 'extern i64 c_val();\nextern i64 cxx_val();\nvoid main() { println("{c_val() + cxx_val()}"); }\n' > mix/main.zk
out=$("$ZARK" run mix/main.zk mix/a.c mix/b.cpp -std=c++17 -std=c11 2>&1)
[ "$out" = "3" ] || fail "mixed_c_cpp_std: expected 3, got: $out"

mkdir -p dl
printf '#define S(x) #x\n#define STR(x) S(x)\nconst char* lib_name(void) { return STR(LIB); }\n' > dl/n.c
printf 'extern u8* lib_name();\nvoid main() { println("{cstr(lib_name())}"); }\n' > dl/main.zk
out=$("$ZARK" run dl/main.zk dl/n.c -DLIB=libfoo.a 2>&1)
[ "$out" = "libfoo.a" ] || fail "define_with_suffix: expected libfoo.a, got: $out"

real=$(compiler_path clang)
mkdir -p shim
printf '#!/bin/sh\necho "$*" >> "%s/clang.log"\nexec "%s" "$@"\n' "$T" "$real" > shim/clang
chmod +x shim/clang
: > clang.log
mkdir -p ch
printf 'long answer(void) { return 42; }\n' > ch/ans.c
cp main.zk ch/main.zk
(cd ch && PATH="$T/shim:$PATH" "$ZARK" build main.zk ans.c -o prog 2>&1) > /dev/null || fail "cache_hit: first build"
n1=$(grep -c -e '-c ans\.c' clang.log)
[ "$n1" -ge 1 ] || fail "cache_hit: the shim did not see the compile"
(cd ch && PATH="$T/shim:$PATH" "$ZARK" build main.zk ans.c -o prog 2>&1) > /dev/null || fail "cache_hit: second build"
n2=$(grep -c -e '-c ans\.c' clang.log)
[ "$n1" = "$n2" ] || fail "cache_hit: the second build ran clang on the source ($n1 -> $n2)"
[ "$(ch/prog)" = "42" ] || fail "cache_hit: wrong output"

mkdir -p he
printf '#define V 1\n' > he/h.h
printf '#include "h.h"\nlong v(void) { return V; }\n' > he/v.c
printf 'extern i64 v();\nvoid main() { println("{v()}"); }\n' > he/main.zk
out=$(cd he && "$ZARK" run main.zk v.c 2>&1)
[ "$out" = "1" ] || fail "cache_header_edit: expected 1, got: $out"
printf '#define V 2\n' > he/h.h
out=$(cd he && "$ZARK" run main.zk v.c 2>&1)
[ "$out" = "2" ] || fail "cache_header_edit: expected 2 after the edit, got: $out"

mkdir -p sb/a sb/b
printf 'long fa(void) { return 1; }\n' > sb/a/util.c
printf 'long fb(void) { return 2; }\n' > sb/b/util.c
printf 'extern i64 fa();\nextern i64 fb();\nvoid main() { println("{fa() + fb()}"); }\n' > sb/main.zk
out=$(cd sb && "$ZARK" run main.zk a/util.c b/util.c 2>&1)
[ "$out" = "3" ] || fail "same_base_name: expected 3, got: $out"

mkdir -p co/c
printf '[package]\nname = "co"\n\n[build]\nsources = ["c/app.cpp"]\nstd = "c++17"\n' > co/zark.toml
printf '#include <string>\n#include <cstdio>\nint main(int argc, char** argv) { std::string s = std::to_string(argc - 1); std::printf("%%s\\n", s.c_str()); return 0; }\n' > co/c/app.cpp
out=$(cd co && "$ZARK" run -- a b 2>&1)
[ "$out" = "2" ] || fail "cpp_only_project run: expected 2, got: $out"
(cd co && "$ZARK" build 2>&1) > /dev/null || fail "cpp_only_project build"
[ "$(co/build/co x y z)" = "3" ] || fail "cpp_only_project build: wrong output"
out=$(cd co && "$ZARK" test 2>&1); code=$?
[ $code -eq 0 ] || fail "cpp_only_project test: exit $code: $out"
case "$out" in *"no tests"*) ;; *) fail "cpp_only_project test: expected no tests, got: $out" ;; esac

mkdir -p em/src
printf '[package]\nname = "em"\n' > em/zark.toml
out=$(cd em && "$ZARK" run 2>&1); code=$?
[ $code -ne 0 ] || fail "missing_main_no_sources: expected a failure"
case "$out" in *src/main.zk*) ;; *) fail "missing_main_no_sources: no mention of src/main.zk in: $out" ;; esac

mkdir -p zl
printf 'export i64 zark_twice(i64 x) { return x * 2; }\n' > zl/lib.zk
printf '#include <stdio.h>\nlong zark_twice(long);\nint main(void) { printf("%%ld\\n", zark_twice(21)); return 0; }\n' > zl/m.c
out=$("$ZARK" run zl/lib.zk zl/m.c 2>&1)
[ "$out" = "42" ] || fail "zark_lib_with_c_main: expected 42, got: $out"
mkdir -p zp/src zp/c
printf '[package]\nname = "zp"\n\n[build]\nsources = ["c/m.c"]\n' > zp/zark.toml
cp zl/lib.zk zp/src/main.zk
cp zl/m.c zp/c/m.c
out=$(cd zp && "$ZARK" run 2>&1)
[ "$out" = "42" ] || fail "zark_lib_with_c_main project: expected 42, got: $out"

mkdir -p ip/inc
printf '#define V 7\n' > ip/inc/v.h
printf '#include <v.h>\nlong answer(void) { return V; }\n' > ip/a.c
cp main.zk ip/main.zk
out=$(cd ip && "$ZARK" run main.zk a.c -isystem inc 2>&1)
[ "$out" = "7" ] || fail "isystem_pair: expected 7, got: $out"
out=$(cd ip && "$ZARK" run main.zk -isystem inc a.c 2>&1)
[ "$out" = "7" ] || fail "isystem_pair before the source: expected 7, got: $out"

mkdir -p ipm/src ipm/inc ipm/inc2
printf '[package]\nname = "ipm"\n\n[build]\nsources = ["a.c"]\ncflags = ["-isystem", "inc", "-isystem", "inc2", "-include", "pre.h"]\n' > ipm/zark.toml
printf '#define V 7\n' > ipm/inc/v.h
printf '#define W 5\n' > ipm/inc2/w.h
printf '#define PRE 1\n' > ipm/pre.h
printf '#include <v.h>\n#include <w.h>\nlong answer(void) { return V * 10 + W + PRE; }\n' > ipm/a.c
printf 'extern i64 answer();\nvoid main() { println("{answer()}"); }\n' > ipm/src/main.zk
out=$(cd ipm && "$ZARK" run 2>&1)
[ "$out" = "76" ] || fail "isystem_pair manifest: expected 76, got: $out"
out=$(cd ipm && "$ZARK" run src/main.zk 2>&1)
[ "$out" = "76" ] || fail "isystem_pair manifest explicit file: expected 76, got: $out"

mkdir -p inp
printf '#define V 8\n' > inp/pre.h
printf 'long answer(void) { return V; }\n' > inp/a.c
cp main.zk inp/main.zk
out=$(cd inp && "$ZARK" run main.zk a.c -include pre.h 2>&1)
[ "$out" = "8" ] || fail "include_pair: expected 8, got: $out"

mkdir -p sd/inc
printf '#define BASE 40\n' > sd/inc/cfg.h
printf '#include "cfg.h"\n#ifdef GONE\n#error gone\n#endif\nlong answer(void) { return ANSWER + BASE; }\n' > sd/ans.c
cp main.zk sd/main.zk
out=$(cd sd && "$ZARK" run main.zk ans.c -I inc -D ANSWER=2 -D GONE=1 -U GONE 2>&1)
[ "$out" = "42" ] || fail "I_space_D_space: expected 42, got: $out"

mkdir -p pd
srcs=""
decls=""
sum=""
for i in 0 1 2 3 4 5 6 7 8 9; do
  printf 'long f%s(void) { return %s; }\n' $i $((i * i)) > pd/s$i.c
  srcs="$srcs s$i.c"
  decls="${decls}extern i64 f$i();\n"
  sum="$sum + f$i()"
done
printf "${decls}void main() { println(\"{0$sum}\"); }\n" > pd/main.zk
ref=""
for jobs in 1 8 1 8 1 8; do
  rm -rf pd/.zark-cache/obj
  out=$(cd pd && ZARK_JOBS=$jobs "$ZARK" run main.zk $srcs 2>&1)
  [ "$out" = "285" ] || fail "parallel_determinism: ZARK_JOBS=$jobs expected 285, got: $out"
  names=$(ls pd/.zark-cache/obj | grep '\.o$')
  [ -n "$ref" ] || ref="$names"
  [ "$names" = "$ref" ] || fail "parallel_determinism: object names differ with ZARK_JOBS=$jobs"
done

mkdir -p cr
cp pd/s*.c cr/
cp pd/main.zk cr/main.zk
(cd cr && "$ZARK" build main.zk $srcs -o p1 > o1.txt 2>&1) &
pid1=$!
(cd cr && "$ZARK" build main.zk $srcs -o p2 > o2.txt 2>&1) &
pid2=$!
wait $pid1 || fail "concurrent_runs: first build failed: $(cat cr/o1.txt)"
wait $pid2 || fail "concurrent_runs: second build failed: $(cat cr/o2.txt)"
[ "$(cr/p1)" = "285" ] && [ "$(cr/p2)" = "285" ] || fail "concurrent_runs: wrong output"

mkdir -p hd
printf '#define V 1\n' > hd/h.h
printf '#include "h.h"\nlong v(void) { return V; }\n' > hd/v.c
cp he/main.zk hd/main.zk
out=$(cd hd && "$ZARK" run main.zk v.c 2>&1)
[ "$out" = "1" ] || fail "cache_header_delete: expected 1, got: $out"
rm hd/h.h
out=$(cd hd && "$ZARK" run main.zk v.c 2>&1); code=$?
[ $code -ne 0 ] || fail "cache_header_delete: expected a failure, got: $out"
case "$out" in *h.h*) ;; *) fail "cache_header_delete: no compile error about h.h in: $out" ;; esac

mkdir -p fc
printf 'long answer(void) { return ANSWER; }\n' > fc/ans.c
cp main.zk fc/main.zk
out=$(cd fc && "$ZARK" run main.zk ans.c -DANSWER=1 2>&1)
[ "$out" = "1" ] || fail "cache_flag_change: expected 1, got: $out"
out=$(cd fc && "$ZARK" run main.zk ans.c -DANSWER=2 2>&1)
[ "$out" = "2" ] || fail "cache_flag_change: expected 2 after the flag change, got: $out"

mkdir -p "sp/s p" "sp/i n"
printf '#define V 5\n' > "sp/i n/h.h"
printf '#include "h.h"\nlong v(void) { return V; }\n' > "sp/s p/v.c"
cp he/main.zk sp/main.zk
(cd sp && PATH="$T/shim:$PATH" "$ZARK" build main.zk "s p/v.c" "-Ii n" -o prog 2>&1) > /dev/null || fail "cache_space_path: first build"
n1=$(grep -c -e '-c s p/v\.c' clang.log)
[ "$n1" -ge 1 ] || fail "cache_space_path: the shim did not see the compile"
(cd sp && PATH="$T/shim:$PATH" "$ZARK" build main.zk "s p/v.c" "-Ii n" -o prog 2>&1) > /dev/null || fail "cache_space_path: second build"
n2=$(grep -c -e '-c s p/v\.c' clang.log)
[ "$n1" = "$n2" ] || fail "cache_space_path: the second build ran clang on the source ($n1 -> $n2)"
[ "$(sp/prog)" = "5" ] || fail "cache_space_path: wrong output"

mkdir -p is
printf '#define V 1\n' > is/h.h
printf '#include "h.h"\nlong v(void) { return V; }\n' > is/v.c
cp he/main.zk is/main.zk
(cd is && PATH="$T/shim:$PATH" "$ZARK" build main.zk v.c -o prog 2>&1) > /dev/null || fail "cache_interrupted_stamp: first build"
n1=$(grep -c -e '-c v\.c' clang.log)
rm is/.zark-cache/obj/*.stamp
printf '#define V 2\n' > is/h.h
printf '#define V 1\n' > is/h.h
(cd is && PATH="$T/shim:$PATH" "$ZARK" build main.zk v.c -o prog 2>&1) > /dev/null || fail "cache_interrupted_stamp: second build"
n2=$(grep -c -e '-c v\.c' clang.log)
[ "$n2" -gt "$n1" ] || fail "cache_interrupted_stamp: a missing stamp was trusted"

mkdir -p ik
printf '#define V 1\n' > ik/h.h
printf '#include "h.h"\nlong v(void) { return V; }\n' > ik/a.c
printf 'long w(void) { return 0; }\n' > ik/b.c
printf 'extern i64 v();\nextern i64 w();\nvoid main() { println("{v() + w()}"); }\n' > ik/main.zk
(cd ik && "$ZARK" build main.zk a.c b.c -o prog 2>&1) > /dev/null || fail "cache_interrupted_stamp: kill setup build"
printf '#define V 2\n' > ik/h.h
printf 'long w(void) { return 1; }\n' > ik/b.c
mkdir -p slow
printf '#!/bin/sh\ncase "$*" in\n*" b.c "*) sleep 3; exit 1;;\nesac\n"%s" "$@"\n' "$real" > slow/clang
chmod +x slow/clang
(cd ik && ZARK_JOBS=2 PATH="$T/slow:$PATH" exec "$ZARK" build main.zk a.c b.c -o prog > /dev/null 2>&1) &
kpid=$!
sleep 1
kill -9 $kpid
wait $kpid 2>/dev/null
printf '#define V 1\n' > ik/h.h
printf 'long w(void) { return 0; }\n' > ik/b.c
out=$(cd ik && "$ZARK" run main.zk a.c b.c 2>&1)
[ "$out" = "1" ] || fail "cache_interrupted_stamp: after a killed build expected 1, got: $out"

if command -v pkg-config >/dev/null; then
  mkdir -p pk/src
  printf '[package]\nname = "pk"\n\n[build]\npkg-config = ["zark-no-such-package"]\n' > pk/zark.toml
  printf 'void main() {}\n' > pk/src/main.zk
  out=$(cd pk && "$ZARK" run 2>&1); code=$?
  [ $code -ne 0 ] || fail "pkg_config_missing_package: expected a failure"
  case "$out" in *zark-no-such-package*) ;; *) fail "pkg_config_missing_package: no package name in: $out" ;; esac
  case "$out" in *error.CompileFailed*) fail "pkg_config_missing_package: stray error name in: $out" ;; esac
  if pkg-config --exists zlib; then
    printf '[package]\nname = "pk"\n\n[build]\npkg-config = ["zlib"]\n' > pk/zark.toml
    printf 'extern u8* zlibVersion();\nvoid main() { println("{zlibVersion() != null}"); }\n' > pk/src/main.zk
    out=$(cd pk && "$ZARK" run 2>&1)
    [ "$out" = "true" ] || fail "pkg_config_ok: expected true, got: $out"
  else
    echo "skip pkg_config_ok: zlib not found by pkg-config"
  fi
else
  echo "skip pkg_config tests: pkg-config is not installed"
fi
echo "ok   cbuild"
