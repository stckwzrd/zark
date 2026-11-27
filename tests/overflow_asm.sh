#!/usr/bin/env bash
# The checked-add peephole is checked in the machine code, not only by tests:
# only 64-bit adds can use `jno`. For i8/i16/i32 the backend extends the
# operands, so OF does not reflect the narrow overflow and the sign trick has
# to stay (this is the bug that tests/panics/add_overflow.zk caught).
cd "$(dirname "$0")/.."
[ "$(uname -s)-$(uname -m)" = "Linux-x86_64" ] || { echo "ok   overflow asm (skipped, needs x86-64 Linux)"; exit 0; }
ZARK=${ZARK:-./build/zark}
command -v objdump >/dev/null || { echo "ok   overflow asm (skipped, no objdump)"; exit 0; }
tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT

cat > "$tmp/t.zk" <<'EOF'
i64 add64(i64 a, i64 b) { return a + b; }
i32 add32(i32 a, i32 b) { return a + b; }
i8 add8(i8 a, i8 b) { return a + b; }
void main() { println(add64(1, 2) + (add32(1, 2) as i64) + (add8(1, 2) as i64)); }
EOF
$ZARK build "$tmp/t.zk" --native -o "$tmp/t" >/dev/null 2>&1 || { echo "FAIL overflow asm: build"; exit 1; }
body() { objdump -d --no-show-raw-insn "$tmp/t" | sed -n "/<vb.$1>:/,/^\$/p"; }

body add64 | grep -q 'jno' || { echo "FAIL overflow asm: i64 add is not a single jno"; exit 1; }
for f in add32 add8; do
  if body "$f" | grep -q 'jno'; then
    echo "FAIL overflow asm: $f used jno, but OF does not reflect a narrow overflow"
    exit 1
  fi
  body "$f" | grep -qE '\band\b' || { echo "FAIL overflow asm: $f lost the sign trick"; exit 1; }
done
echo "ok   overflow asm (i64 is one jno; i32/i8 keep the sign trick)"
