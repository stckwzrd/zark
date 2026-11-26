#!/usr/bin/env bash
# The guide's `zark run` blocks are executed by docs-src/build.js. Build into a
# temporary directory, then check that the committed site is what the sources
# produce: a change to a page or to a diagnostic must be regenerated, not left
# to drift (docs/memory.html once shipped five bogus errors from the compiler).
cd "$(dirname "$0")/.."
ZARK=${ZARK:-./build/zark}
ZARK=$(realpath "$ZARK")
if ! command -v node >/dev/null 2>&1; then
    echo "ok   docs (skipped, node is not installed)"; exit 0
fi
if [ ! -d docs-src/node_modules ]; then
    echo "ok   docs (skipped, run npm install in docs-src)"; exit 0
fi
out=$(mktemp -d)
cache="${out}.cache.json"
log="${out}.log"
diffout="${out}.diff"
trap 'rm -rf "$out" "$cache" "$log" "$diffout"' EXIT
if ! DOCS_OUT="$out" DOCS_CACHE="$cache" ZARK="$ZARK" timeout 1800 node docs-src/build.js > "$log" 2>&1; then
    echo "FAIL docs"
    tail -30 "$log"
    exit 1
fi
if ! diff -r "$out" docs > "$diffout" 2>&1; then
    echo "FAIL docs (docs/ is stale; regenerate with DOCS_OUT=docs node docs-src/build.js)"
    head -60 "$diffout"
    exit 1
fi
echo "ok   docs (all code blocks ran, docs/ is up to date)"
