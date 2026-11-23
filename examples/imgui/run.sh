#!/bin/sh
set -e
cd "$(dirname "$0")"
zark="${ZARK:-zark}"
pin=2a6a93fccd10f275ee9206167dc9698f6f00fac1

if [ ! -d deps/cimgui ]; then
    mkdir -p deps/cimgui
    git -C deps/cimgui init -q
    git -C deps/cimgui fetch -q --depth 1 https://github.com/cimgui/cimgui "$pin"
    git -C deps/cimgui checkout -q FETCH_HEAD
    git -C deps/cimgui submodule update -q --init --depth 1
fi

exec "$zark" run -- "$@"
