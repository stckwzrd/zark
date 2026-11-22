#!/usr/bin/env bash
# Projects: zark new, zark.toml, path and git dependencies, C sources, zark test in a project.
ZARK=$(realpath "${ZARK:-./build/zark}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL project: $*"; exit 1; }
cd "$T"
"$ZARK" new hello >/dev/null || fail "zark new"
(cd hello && [ "$("$ZARK" run -- --name Zark)" = "Hello, Zark!" ]) || fail "run in a new project"
(cd hello && "$ZARK" build >/dev/null && [ "$(./build/hello)" = "Hello, world!" ]) || fail "build in a new project"
(cd hello && "$ZARK" test | grep -q "1 passed, 0 failed") || fail "test in a new project"

mkdir -p utils/src app/src/sub app/c app/tests
printf '[package]\nname = "utils"\nlib = "src/lib.zk"\n' > utils/zark.toml
printf 'import "std/thread" as thread;\ni64 answer() { return 42; }\n' > utils/src/lib.zk
printf 'i64 twice(i64 x) { return x * 2; }\n' > utils/src/extra.zk
printf 'long fast_add(long a, long b) { return a + b; }\n' > app/c/fast.c
printf 'str name() { return "helper"; }\n' > app/src/sub/helper.zk
deps='utils = { path = "../utils" }'
if command -v git >/dev/null; then
  mkdir -p mathc/src mathc/c
  printf '[package]\nname = "mathc"\n[build]\nsources = ["c/mul.c"]\n' > mathc/zark.toml
  printf 'extern i64 c_mul(i64 a, i64 b);\ni64 mul(i64 a, i64 b) { return c_mul(a, b); }\n' > mathc/src/lib.zk
  printf 'long c_mul(long a, long b) { return a * b; }\n' > mathc/c/mul.c
  (cd mathc && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm init && git tag v1) || fail "git setup"
  deps="$deps
mathc = { git = \"file://$T/mathc\", rev = \"v1\" }"
  mul='m::mul(6, 7)'; imp='import "mathc" as m;'
else
  mul='42'; imp=''
fi
cat > app/zark.toml <<TOML
[package]
name = "app"   # comment

[build]
sources = ["c/fast.c"]
libs = ["m"]

[dependencies]
$deps
TOML
cat > app/src/main.zk <<ZARK
import "utils" as u;
import "utils/extra" as ex;
import "sub/helper.zk" as h;
$imp
extern i64 fast_add(i64 a, i64 b);
void main() { println(u::answer(), ex::twice(21), $mul, fast_add(40, 2), h::name(), sqrt(16.0)); }
ZARK
printf 'import "utils" as u;\ntest "answer" { assert(u::answer() == 42); }\n' > app/tests/basic.zk
want="42 42 42 42 helper 4"
(cd app && [ "$("$ZARK" run 2>/dev/null)" = "$want" ]) || fail "run with dependencies"
(cd app/src/sub && [ "$("$ZARK" run)" = "$want" ]) || fail "run from a subdirectory"
[ "$("$ZARK" run "$T/app/src/main.zk")" = "$want" ] || fail "run an explicit file of a project"
(cd app && "$ZARK" build -O >/dev/null && [ "$(./build/app)" = "$want" ]) || fail "build -O with dependencies"
(cd app && "$ZARK" test | grep -q "ok   answer") || fail "test in a project"
printf '[package]\nname = "x\n' > app/zark.toml
(cd app && "$ZARK" run 2>&1 | grep -q "zark.toml:2: error: unterminated string") || fail "manifest error message"
echo "ok   projects (zark new, zark.toml, path and git dependencies, C sources)"
