#!/bin/sh
set -e
cd "$(dirname "$0")"
prefix="${PREFIX:-$HOME/.local}"

if [ ! -x build/vibe ]; then ./bootstrap.sh; fi

mkdir -p "$prefix/bin"
cp build/vibe "$prefix/bin/vibe.new"
mv -f "$prefix/bin/vibe.new" "$prefix/bin/vibe"
echo "installed $prefix/bin/vibe"
case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) echo "add $prefix/bin to PATH" ;;
esac
