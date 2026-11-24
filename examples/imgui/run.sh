#!/bin/sh
set -e
cd "$(dirname "$0")"
zark="${ZARK:-zark}"
pin=6d32174508fb8c518e7a832cc1d571fadd5cba76

probe=$(mktemp -d)
printf 'struct ZarkCxxProbe { int n; };\n' > "$probe/probe.hpp"
if ! "$zark" cbind "$probe/probe.hpp" >/dev/null 2>&1; then
    rm -rf "$probe"
    echo "run.sh: this example needs a zark with C++ header binding (zark cbind x.hpp)" >&2
    echo "run it with a fresh compiler, for example: ZARK=../../build/zark ./run.sh" >&2
    exit 1
fi
rm -rf "$probe"

if [ ! -f deps/imgui/imgui.h ]; then
    rm -rf deps/imgui
    mkdir -p deps/imgui
    git -C deps/imgui init -q
    git -C deps/imgui fetch -q --depth 1 https://github.com/ocornut/imgui "$pin"
    git -C deps/imgui checkout -q FETCH_HEAD
fi

exec "$zark" run -- "$@"
