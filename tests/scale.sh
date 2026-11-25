#!/usr/bin/env bash
cd "$(dirname "$0")/.."
ZARK=${ZARK:-./build/zark}
command -v timeout >/dev/null || timeout() { shift; "$@"; }
MEM=3000000
TMO=30
if grep -aqm1 "__asan" "$ZARK" 2>/dev/null; then
    # AddressSanitizer reserves terabytes of virtual address space; keep the
    # memory bound only for normal builds and give the instrumented one time.
    MEM=unlimited
    TMO=180
fi
( ulimit -v "$MEM" ) 2>/dev/null || { echo "ok   scale (skipped, ulimit -v is not available)"; exit 0; }
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
open(d + "/big.zk", "w").write("\n".join(head + body + ["    println(sum);", "}"]) + "\n")
live = [f"    auto p{i} = l.at(0);" for i in range(600)]
open(d + "/live.zk", "w").write("\n".join(head + live + ["    println(sum);", "}"]) + "\n")
guards = ["void main() {", "    i64[8] a;", "    i64 s = 0;", "    i64 k = 3;"]
for j in range(8000):
    guards.append(f"    s += a[{j % 8}] / ({j % 8} + k);")
guards += ["    println(s);", "}"]
open(d + "/guards.zk", "w").write("\n".join(guards) + "\n")
PY
fail() { echo "FAIL scale ($1)"; head -3 "$dir/err"; exit 1; }
( ulimit -v "$MEM"; timeout "$TMO" "$ZARK" ir "$dir/big.zk" >/dev/null 2>"$dir/err" ) || fail "2000 loops"
echo "ok   scale (a function with 2000 loops compiles in bounded time and memory)"
( ulimit -v "$MEM"; timeout "$TMO" "$ZARK" ir "$dir/guards.zk" >/dev/null 2>"$dir/err" ) || fail "8000 checked operations"
echo "ok   scale (a function with 8000 checked operations compiles in time)"
if ( ulimit -v "$MEM"; timeout "$TMO" "$ZARK" ir "$dir/live.zk" >/dev/null 2>"$dir/err" ); then fail "600 live borrows must be reported"; fi
grep -q "tracks more than 512" "$dir/err" || fail "no clear message for too many tracked variables"

# Compile-time regression guard: the self-hosted source is the largest input.
if ! python3 - "$ZARK" <<'PY'
import os, subprocess, sys, time
z = sys.argv[1]
limit = float(os.environ.get("ZARK_MAX_SELFHOST_MS", "15000"))
t = time.time()
p = subprocess.run([z, "ir", "selfhost/main.zk"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
ms = (time.time() - t) * 1000
if p.returncode != 0:
    print(f"FAIL scale (selfhost ir exited {p.returncode})")
    sys.exit(1)
if ms > limit:
    print(f"FAIL scale (selfhost ir took {ms:.0f} ms, limit {limit:.0f})")
    sys.exit(1)
print(f"ok   scale (selfhost ir {ms:.0f} ms)")
PY
then exit 1; fi
