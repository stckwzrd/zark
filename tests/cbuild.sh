#!/usr/bin/env bash
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
printf '[package]\nname = "mf"\n\n[build]\nsources = ["c/s.cpp"]\ninclude = ["inc dir"]\ndefines = ["N=3"]\nstd = "c++17"\ncflags = ["-DM=5"]\nlibs = ["stdc++"]\n' > mf/zark.toml
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

if command -v pkg-config >/dev/null; then
  mkdir -p pk/src
  printf '[package]\nname = "pk"\n\n[build]\npkg-config = ["zark-no-such-package"]\n' > pk/zark.toml
  printf 'void main() {}\n' > pk/src/main.zk
  out=$(cd pk && "$ZARK" run 2>&1); code=$?
  [ $code -ne 0 ] || fail "pkg_config_missing_package: expected a failure"
  case "$out" in *zark-no-such-package*) ;; *) fail "pkg_config_missing_package: no package name in: $out" ;; esac
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
