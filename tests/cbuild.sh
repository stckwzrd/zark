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
echo "ok   cbuild"
