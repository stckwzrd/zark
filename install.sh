#!/bin/sh
set -e
cd "$(dirname "$0")"
prefix="${PREFIX:-$HOME/.local}"

if [ ! -x build/zark ]; then ./bootstrap.sh; fi

mkdir -p "$prefix/bin"
cp build/zark "$prefix/bin/zark.new"
mv -f "$prefix/bin/zark.new" "$prefix/bin/zark"
echo "installed $prefix/bin/zark"
case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) echo "add $prefix/bin to PATH" ;;
esac
