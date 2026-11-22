#!/usr/bin/env bash
cd "$(dirname "$0")"
ZARK=${ZARK:-../../build/zark}
OUT=${OUT:-.zark-cache}
mkdir -p $OUT
$ZARK build kernel.zk boot.S -Wl,-T,linker.ld --freestanding $FLAGS -o $OUT/kernel.elf 2>/dev/null || exit 1
objcopy -O elf32-i386 $OUT/kernel.elf $OUT/kernel32.elf || exit 1
timeout 20 qemu-system-x86_64 -kernel $OUT/kernel32.elf -display none -serial stdio -device isa-debug-exit,iobase=0xf4,iosize=0x04 -no-reboot
[ $? -eq 1 ]
