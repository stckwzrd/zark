#!/usr/bin/env sh
# Build and install the extension into VS Code (or code-oss) in one step.
set -eu
cd "$(dirname "$0")"

if ! command -v code >/dev/null 2>&1 && ! command -v code-oss >/dev/null 2>&1; then
    echo "install.sh: neither 'code' nor 'code-oss' is on PATH" >&2
    exit 1
fi

if [ ! -d node_modules ]; then
    npm ci --no-audit --no-fund
fi
vsix=$(python3 pack.py)
if command -v code >/dev/null 2>&1; then
    code --install-extension "$vsix" --force
else
    code-oss --install-extension "$vsix" --force
fi
