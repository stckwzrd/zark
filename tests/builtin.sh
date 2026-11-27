#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ZARK=${ZARK:-./build/zark}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/target.zk" <<'EOF'
import "std/builtin" as b;
comptime if (b::is_windows) { import "missing-platform-only.zk"; }
comptime if (b::os == "macos" && b::arch == "aarch64" && b::abi == "aapcs64" && b::endian == "little") {
    export i64 target_value() { return 17; }
} else if (b::is_linux && b::is_x86_64) {
    export i64 target_value() { return 29; }
} else {
    export i64 target_value() { return 41; }
}
EOF
"$ZARK" ir "$tmp/target.zk" --os macos --arch aarch64 > "$tmp/mac.ll"
"$ZARK" ir "$tmp/target.zk" --os linux --arch x86_64 > "$tmp/linux.ll"
"$ZARK" ir "$tmp/target.zk" --os linux --arch aarch64 > "$tmp/arm.ll"
grep -q 'ret i64 17' "$tmp/mac.ll"
grep -q 'ret i64 29' "$tmp/linux.ll"
grep -q 'ret i64 41' "$tmp/arm.ll"
cat > "$tmp/ct-target.zk" <<'EOF'
import "std/builtin" as b;
i64 ct_target() {
    comptime if (b::os == "macos" && b::arch == "aarch64") { return 17; }
    else { return 99; }
}
!void main() { println(comptime ct_target()); }
EOF
"$ZARK" ir "$tmp/ct-target.zk" --os macos --arch aarch64 > "$tmp/ct-target.ll"
grep -Fq '@ct.1 = private unnamed_addr constant [8 x i8] c"\11\00\00\00\00\00\00\00"' "$tmp/ct-target.ll"
cat > "$tmp/mode.zk" <<'EOF'
import "std/builtin" as b;
i64 get_mode() {
    comptime if (b::optimized && !b::safety) { return 123; }
    else { return 321; }
}
!void main() { println(b::optimized, b::safety, b::overflow_checks, b::fast, comptime get_mode()); }
EOF
"$ZARK" run "$tmp/mode.zk" > "$tmp/debug.out"
"$ZARK" run "$tmp/mode.zk" -O > "$tmp/optimized.out"
"$ZARK" run "$tmp/mode.zk" --release > "$tmp/release.out"
"$ZARK" run "$tmp/mode.zk" --release --check-overflow > "$tmp/checked.out"
"$ZARK" run "$tmp/mode.zk" --fast > "$tmp/fast.out"
grep -qx 'false true true false 321' "$tmp/debug.out"
grep -qx 'true true true false 321' "$tmp/optimized.out"
grep -qx 'true false false false 123' "$tmp/release.out"
grep -qx 'true false true false 123' "$tmp/checked.out"
grep -qx 'true false false true 123' "$tmp/fast.out"
cat > "$tmp/invalid.zk" <<'EOF'
import "std/builtin" as b;
void main() { comptime if (b::unknown) { } }
EOF
if "$ZARK" ir "$tmp/invalid.zk" > "$tmp/error.out" 2>&1; then
    echo "FAIL builtin: unknown flag was accepted"
    exit 1
fi
grep -q 'comptime if requires boolean literals or std/builtin flags' "$tmp/error.out"
echo 'ok   builtin target and build modes'
