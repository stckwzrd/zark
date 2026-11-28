#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ZARK=$(realpath "${ZARK:-./build/zark}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git config --get user.email >/dev/null 2>&1 || export GIT_AUTHOR_EMAIL=test@example.com
git config --get user.name  >/dev/null 2>&1 || export GIT_AUTHOR_NAME=Test

commit() { git -c user.name=Test -c user.email=test@example.com commit -qm "$1"; }

mkdir -p "$tmp/dep/src"
printf '[package]\nname = "dep"\nversion = "0.1.0"\nlib = "src/lib.zk"\n' > "$tmp/dep/zark.toml"
echo 'const auto VALUE = 42;' > "$tmp/dep/src/lib.zk"
( cd "$tmp/dep" && git init -q -b main && git add -A && commit v1 && git tag v1 )

mkdir -p "$tmp/app/src"
cat > "$tmp/app/zark.toml" <<EOF
[package]
name = "app"
version = "0.1.0"
main = "src/main.zk"

[dependencies]
dep = { git = "$tmp/dep", rev = "main" }
EOF
echo 'import "dep" as dep;
!void main() { println(dep::VALUE); }' > "$tmp/app/src/main.zk"

cd "$tmp/app"
"$ZARK" update >/dev/null 2>&1
[ -f zark.lock ] || { echo "FAIL: update did not write zark.lock"; exit 1; }
[ "$("$ZARK" run 2>/dev/null)" = 42 ] || { echo "FAIL: first run is not 42"; exit 1; }

echo 'const auto VALUE = 99;' > "$tmp/dep/src/lib.zk"
( cd "$tmp/dep" && git add -A && commit v2 )
[ "$("$ZARK" run 2>/dev/null)" = 42 ] || { echo "FAIL: a moved dependency changed a locked build"; exit 1; }

"$ZARK" update >/dev/null 2>&1
[ "$("$ZARK" run 2>/dev/null)" = 99 ] || { echo "FAIL: update did not re-pin"; exit 1; }

rm -rf .zark
"$ZARK" fetch >/dev/null 2>&1
[ "$("$ZARK" run 2>/dev/null)" = 99 ] || { echo "FAIL: fetch did not restore the lock"; exit 1; }

cp zark.lock good.lock
python3 -c 'import sys,re; p=sys.argv[1]; s=open(p).read(); open(p,"w").write(re.sub(r"commit = \".*\"", "commit = \"0000000000000000000000000000000000000000\"", s))' zark.lock
if "$ZARK" run >/dev/null 2>&1; then echo "FAIL: a wrong commit in the lock was accepted"; exit 1; fi
cp good.lock zark.lock

mkdir -p "$tmp/lib2/src"
printf '[package]\nname = "lib2"\nversion = "0.1.0"\nlib = "src/lib.zk"\n' > "$tmp/lib2/zark.toml"
echo 'const auto TWO = 7;' > "$tmp/lib2/src/lib.zk"
( cd "$tmp/lib2" && git init -q -b main && git add -A && commit lib2 )
"$ZARK" add "$tmp/lib2" --rev main >/dev/null 2>&1
grep -q '^\[package.lib2\]' zark.lock || { echo "FAIL: add did not lock lib2"; exit 1; }
if "$ZARK" add "$tmp/lib2" --rev main >/dev/null 2>&1; then echo "FAIL: add accepted a dependency that is already there"; exit 1; fi
[ "$(grep -c '^lib2' zark.toml)" = 1 ] || { echo "FAIL: add wrote the dependency twice"; exit 1; }
"$ZARK" remove lib2 >/dev/null 2>&1
if grep -q '^\[package.lib2\]' zark.lock; then echo "FAIL: remove left lib2 in the lock"; exit 1; fi

python3 -c 'import sys,re; p=sys.argv[1]; s=open(p).read(); open(p,"w").write(re.sub(r"rev = \"main\"", "rev = \"v1\"", s))' zark.toml
"$ZARK" update >/dev/null 2>&1
[ "$("$ZARK" run 2>/dev/null)" = 42 ] || { echo "FAIL: a changed rev did not replace the lock entry"; exit 1; }

python3 -c 'import sys,re; p=sys.argv[1]; s=open(p).read(); open(p,"w").write(re.sub(r"^dep = .*\n", "", s, flags=re.M))' zark.toml
"$ZARK" update >/dev/null 2>&1
if grep -q '^\[package.dep\]' zark.lock; then echo "FAIL: update kept a dependency the manifest no longer has"; exit 1; fi

echo "pkg ok"
