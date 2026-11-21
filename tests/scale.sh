#!/usr/bin/env bash
cd "$(dirname "$0")/.."
VIBE=${VIBE:-./build/vibe}
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
python3 - "$dir/big.vibe" <<'PY'
import sys
n = 2000
lines = ["void main() {", "    auto l = List<i64>::init(c_allocator());", "    defer l.deinit();", "    l.push(1) catch return;", "    i64 sum = 0;"]
for i in range(n):
    lines.append(f"    auto p{i} = l.at(0);")
    lines.append(f"    for (auto x : l) {{ sum += x + *p{i}; }}")
    lines.append(f"    if (sum > {i}) {{ sum -= 1; }} else {{ sum += 2; }}")
lines.append("    println(sum);")
lines.append("}")
open(sys.argv[1], "w").write("\n".join(lines) + "\n")
PY
if ( ulimit -v 3000000; timeout 30 "$VIBE" ir "$dir/big.vibe" >/dev/null 2>"$dir/err" ); then
  echo "ok   scale (a 2000-loop function compiles in bounded time and memory)"
else
  echo "FAIL scale"; head -3 "$dir/err"; exit 1
fi
