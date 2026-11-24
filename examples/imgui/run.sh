#!/bin/sh
set -e
cd "$(dirname "$0")"
zark="${ZARK:-zark}"
pin=6d32174508fb8c518e7a832cc1d571fadd5cba76

if [ ! -f deps/imgui/imgui.h ]; then
    rm -rf deps/imgui
    mkdir -p deps/imgui
    git -C deps/imgui init -q
    git -C deps/imgui fetch -q --depth 1 https://github.com/ocornut/imgui "$pin"
    git -C deps/imgui checkout -q FETCH_HEAD
fi

exec "$zark" run -- "$@"
