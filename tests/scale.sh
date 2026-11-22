#!/usr/bin/env bash
cd "$(dirname "$0")/.."
VIBE=${VIBE:-./build/vibe}
command -v timeout >/dev/null || timeout() { shift; "$@"; }
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
python3 - "$dir" <<'PY'
import sys
d = sys.argv[1]
head = ["void main() {", "    auto l = List<i64>::init(c_allocator());", "    defer l.deinit();", "    l.push(1) catch return;", "    i64 sum = 0;"]
body = []
for i in range(2000):
    body.append("    {")
    body.append(f"        auto p{i} = l.at(0);")
    body.append(f"        for (auto x : l) {{ sum += x + *p{i}; }}")
    body.append(f"        if (sum > {i}) {{ sum -= 1; }} else {{ sum += 2; }}")
    body.append("    }")
open(d + "/big.vibe", "w").write("\n".join(head + body + ["    println(sum);", "}"]) + "\n")
live = [f"    auto p{i} = l.at(0);" for i in range(600)]
open(d + "/live.vibe", "w").write("\n".join(head + live + ["    println(sum);", "}"]) + "\n")
guards = ["void main() {", "    i64[8] a;", "    i64 s = 0;", "    i64 k = 3;"]
for j in range(8000):
    guards.append(f"    s += a[{j % 8}] / ({j % 8} + k);")
guards += ["    println(s);", "}"]
open(d + "/guards.vibe", "w").write("\n".join(guards) + "\n")
PY
fail() { echo "FAIL scale ($1)"; head -3 "$dir/err"; exit 1; }
( ulimit -v 3000000; timeout 30 "$VIBE" ir "$dir/big.vibe" >/dev/null 2>"$dir/err" ) || fail "2000 loops"
echo "ok   scale (a function with 2000 loops compiles in bounded time and memory)"
( ulimit -v 3000000; timeout 30 "$VIBE" ir "$dir/guards.vibe" >/dev/null 2>"$dir/err" ) || fail "8000 checked operations"
echo "ok   scale (a function with 8000 checked operations compiles in time)"
if ( ulimit -v 3000000; timeout 30 "$VIBE" ir "$dir/live.vibe" >/dev/null 2>"$dir/err" ); then fail "600 live borrows must be reported"; fi
grep -q "tracks more than 512" "$dir/err" || fail "no clear message for too many tracked variables"
