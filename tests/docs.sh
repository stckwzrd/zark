#!/usr/bin/env bash
# The guide's `zark run` blocks are executed by docs-src/build.js. Run it into a
# temporary directory so the check does not dirty the published docs.
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
cache="$out/cache.json"
trap 'rm -rf "$out"' EXIT
if DOCS_OUT="$out" DOCS_CACHE="$cache" ZARK="$ZARK" timeout 1800 node docs-src/build.js > "$out/log" 2>&1; then
    echo "ok   docs (all code blocks ran)"
else
    echo "FAIL docs"
    tail -30 "$out/log"
    exit 1
fi
