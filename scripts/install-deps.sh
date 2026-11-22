#!/bin/sh
set -e
if [ "$(id -u)" = 0 ]; then sudo=""; else sudo="sudo"; fi

if command -v apt-get >/dev/null 2>&1; then
    $sudo apt-get update
    $sudo apt-get install -y clang binutils diffutils gzip make bash git python3
elif command -v dnf >/dev/null 2>&1; then
    $sudo dnf install -y clang binutils diffutils gzip make bash git python3 glibc-devel
elif command -v pacman >/dev/null 2>&1; then
    $sudo pacman -Syu --needed --noconfirm clang binutils diffutils gzip make bash git python glibc linux-api-headers
elif command -v apk >/dev/null 2>&1; then
    $sudo apk add --no-cache clang gcc binutils musl-dev diffutils gzip make bash git python3
elif command -v zypper >/dev/null 2>&1; then
    $sudo zypper --non-interactive install clang binutils diffutils gzip make bash git python3 glibc-devel
elif command -v xbps-install >/dev/null 2>&1; then
    $sudo xbps-install -Sy clang binutils diffutils gzip make bash git python3
elif [ "$(uname -s)" = "Darwin" ]; then
    if ! command -v clang >/dev/null 2>&1; then xcode-select --install; fi
else
    echo "unknown system: install clang (18 or newer), binutils, diffutils, gzip, bash and make by hand" >&2
    exit 1
fi
