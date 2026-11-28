#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ZARK=${ZARK:-./build/zark}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for side in left right; do
    cat > "$tmp/check.zk" <<EOF
!void main() {
    auto left = List<i64>::init(c_allocator());
    defer left.deinit();
    auto right = List<i64>::init(c_allocator());
    defer right.deinit();
    left.push(1)?; right.push(2)?;
    for (auto a : left, auto b : right) { $side.push(a + b)?; }
}
EOF
    if "$ZARK" ir "$tmp/check.zk" > "$tmp/out" 2>&1; then
        echo "FAIL paired iteration: mutation of $side accepted"
        exit 1
    fi
    grep -q "is changed by 'push' while this loop is still iterating" "$tmp/out"
done
cat > "$tmp/check.zk" <<'EOF'
!void main() {
    auto xs = List<str>::init(c_allocator());
    defer xs.deinit();
    xs.push("hello")?;
    for (auto x : xs, auto y : xs.pop()?) { break; }
}
EOF
if "$ZARK" ir "$tmp/check.zk" > "$tmp/out" 2>&1; then
    echo 'FAIL paired iteration: later source invalidated the earlier source'
    exit 1
fi
grep -q "may have moved or freed" "$tmp/out"
cat > "$tmp/check.zk" <<'EOF'
!void main() {
    auto m = HashMap<i64, i64>::init(c_allocator());
    defer m.deinit();
    m.put(1, 2)?;
    for (auto [key, value] : m.iter()) { m.clear(); }
}
EOF
if "$ZARK" ir "$tmp/check.zk" > "$tmp/out" 2>&1; then
    echo 'FAIL iterator: clearing the map was accepted'
    exit 1
fi
grep -q "is changed by 'clear' while this loop is still iterating" "$tmp/out"
cat > "$tmp/check.zk" <<'EOF'
!void main() {
    auto set = HashSet<i64>::init(c_allocator());
    defer set.deinit();
    _ = set.add(1)?;
    for (auto [x, present] : set.iter()) { _ = set.remove(x); }
}
EOF
if "$ZARK" ir "$tmp/check.zk" > "$tmp/out" 2>&1; then
    echo 'FAIL iterator: changing the set was accepted'
    exit 1
fi
grep -q "is changed by 'remove' while this loop is still iterating" "$tmp/out"
for mode in single paired; do
    body='for (auto x : Bad{}) { }'
    if [ "$mode" = paired ]; then body='for (auto x : Bad{}, auto y : 0..1) { }'; fi
    cat > "$tmp/check.zk" <<EOF
struct Bad { bool next() { return true; } void value() { } }
void main() { $body }
EOF
    if "$ZARK" ir "$tmp/check.zk" > "$tmp/out" 2>&1; then
        echo "FAIL iterator: void value() accepted in $mode loop"
        exit 1
    fi
    grep -q 'must return a value' "$tmp/out"
done
for mode in single paired; do
    body='for (auto x : OwnedCounter::init()) { }'
    if [ "$mode" = paired ]; then body='for (auto x : OwnedCounter::init(), auto y : 0..1) { }'; fi
    cat > "$tmp/check.zk" <<EOF
owned struct OwnedCounter {
    static Self init() { return Self{}; }
    bool next() { return false; }
    i64 value() { return 0; }
    void deinit() move { }
}
void main() { $body }
EOF
    if "$ZARK" ir "$tmp/check.zk" > "$tmp/out" 2>&1; then
        echo "FAIL iterator: temporary resource accepted in $mode loop"
        exit 1
    fi
    grep -q 'a resource iterator must be stored in a variable and released explicitly' "$tmp/out"
done
if command -v timeout >/dev/null 2>&1; then timeout 20 python3 tests/iteration_lsp.py "$ZARK";
else python3 tests/iteration_lsp.py "$ZARK"; fi
echo 'ok   iterator invalidation'
