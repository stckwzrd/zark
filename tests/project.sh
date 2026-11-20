#!/usr/bin/env bash
# Projects: vibe new, vibe.toml, path and git dependencies, C sources, vibe test in a project.
VIBE=$(realpath "${VIBE:-./build/vibe}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL project: $*"; exit 1; }
cd "$T"
"$VIBE" new hello >/dev/null || fail "vibe new"
(cd hello && [ "$("$VIBE" run -- --name Vibe)" = "Hello, Vibe!" ]) || fail "run in a new project"
(cd hello && "$VIBE" build >/dev/null && [ "$(./build/hello)" = "Hello, world!" ]) || fail "build in a new project"
(cd hello && "$VIBE" test | grep -q "1 passed, 0 failed") || fail "test in a new project"

mkdir -p utils/src app/src/sub app/c app/tests
printf '[package]\nname = "utils"\nlib = "src/lib.vibe"\n' > utils/vibe.toml
printf 'import "std/thread" as thread;\ni64 answer() { return 42; }\n' > utils/src/lib.vibe
printf 'i64 twice(i64 x) { return x * 2; }\n' > utils/src/extra.vibe
printf 'long fast_add(long a, long b) { return a + b; }\n' > app/c/fast.c
printf 'str name() { return "helper"; }\n' > app/src/sub/helper.vibe
deps='utils = { path = "../utils" }'
if command -v git >/dev/null; then
  mkdir -p mathc/src mathc/c
  printf '[package]\nname = "mathc"\n[build]\nsources = ["c/mul.c"]\n' > mathc/vibe.toml
  printf 'extern i64 c_mul(i64 a, i64 b);\ni64 mul(i64 a, i64 b) { return c_mul(a, b); }\n' > mathc/src/lib.vibe
  printf 'long c_mul(long a, long b) { return a * b; }\n' > mathc/c/mul.c
  (cd mathc && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm init && git tag v1) || fail "git setup"
  deps="$deps
mathc = { git = \"file://$T/mathc\", rev = \"v1\" }"
  mul='m::mul(6, 7)'; imp='import "mathc" as m;'
else
  mul='42'; imp=''
fi
cat > app/vibe.toml <<TOML
[package]
name = "app"   # comment

[build]
sources = ["c/fast.c"]
libs = ["m"]

[dependencies]
$deps
TOML
cat > app/src/main.vibe <<VIBE
import "utils" as u;
import "utils/extra" as ex;
import "sub/helper.vibe" as h;
$imp
extern i64 fast_add(i64 a, i64 b);
void main() { println(u::answer(), ex::twice(21), $mul, fast_add(40, 2), h::name(), sqrt(16.0)); }
VIBE
printf 'import "utils" as u;\ntest "answer" { assert(u::answer() == 42); }\n' > app/tests/basic.vibe
want="42 42 42 42 helper 4"
(cd app && [ "$("$VIBE" run 2>/dev/null)" = "$want" ]) || fail "run with dependencies"
(cd app/src/sub && [ "$("$VIBE" run)" = "$want" ]) || fail "run from a subdirectory"
[ "$("$VIBE" run "$T/app/src/main.vibe")" = "$want" ] || fail "run an explicit file of a project"
(cd app && "$VIBE" build -O >/dev/null && [ "$(./build/app)" = "$want" ]) || fail "build -O with dependencies"
(cd app && "$VIBE" test | grep -q "ok   answer") || fail "test in a project"
printf '[package]\nname = "x\n' > app/vibe.toml
(cd app && "$VIBE" run 2>&1 | grep -q "vibe.toml:2: error: unterminated string") || fail "manifest error message"
echo "ok   projects (vibe new, vibe.toml, path and git dependencies, C sources)"
