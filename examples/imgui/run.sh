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

if [ ! -f deps/libcimgui.a ]; then
    cd deps/cimgui
    flags="-O2 -fno-exceptions -fno-rtti -Iimgui -Iimgui/backends -DCIMGUI_USE_SDL2 -DCIMGUI_USE_OPENGL3 $(pkg-config --cflags sdl2)"
    mkdir -p ../obj
    for f in cimgui.cpp cimgui_impl.cpp imgui/imgui.cpp imgui/imgui_draw.cpp imgui/imgui_demo.cpp imgui/imgui_tables.cpp imgui/imgui_widgets.cpp imgui/backends/imgui_impl_sdl2.cpp imgui/backends/imgui_impl_opengl3.cpp; do
        clang++ $flags '-DIMGUI_IMPL_API=extern "C"' -c "$f" -o "../obj/$(basename "$f" .cpp).o" &
    done
    wait
    ar rcs ../libcimgui.a ../obj/*.o
    cd ../..
fi

exec "$zark" run main.zk deps/libcimgui.a -lSDL2 -lGL -lstdc++ -- "$@"
