---
title: Drivers and low-level code
order: 30.5
section: Interop and tools
description: volatile, packed struct, inline asm, Cpu, Port, Bits, atomics, building without libc and a kernel that boots in QEMU
---

Zark is suited to drivers and kernels: device registers are described with structs, privileged instructions are called like ordinary functions, and the program is built without libc. Everything you need is built into the language and the prelude. No macros, no `#pragma`, no compiler attributes.

| Task | In C | In Zark |
|---|---|---|
| a device register | `volatile uint32_t *` and macros | `volatile u32* reg` or `volatile u32` in a `struct` |
| a descriptor format | `__attribute__((packed))` | `packed struct` |
| I/O ports | `asm volatile` with constraints | `Port::in8(p)`, `Port::out8(p, v)` |
| `cli`, `hlt`, `rdtsc`, `cr3`, MSRs | your own inline asm for each | `Cpu::cli()`, `Cpu::halt()`, `Cpu::rdtsc()`, `Cpu::cr3()`, `Cpu::rdmsr(n)` |
| register bits | masks and shifts by hand | `Bits::get(v, 7, 4)`, `Bits::set(v, 7, 4, x)` |
| atomic operations, a spinlock | `<stdatomic.h>` | `Atomic::cas32(...)`, `Spinlock` |
| no libc | `-nostdlib -ffreestanding` and scripts | `--freestanding` |

## `volatile`

`volatile` goes before the type and means that every read and write goes to memory: the compiler does not merge or drop them. This is needed for device registers.

```zark run
struct Uart {
    volatile u32 data;
    volatile u32 status;
    volatile u32 control;
}

void main() {
    Uart dev;
    dev.status = 1;
    volatile u32* ctrl = &dev.control;
    *ctrl = 0xA0;
    *ctrl |= 1;
    println(dev.status, *ctrl);
}
```

`volatile` applies to what lies at the address: `volatile u32* p` is a pointer to a `volatile u32`. A field `volatile u32 data` and a variable `volatile u32 x` work too. The width of an access always equals the width of the type: `volatile u8*` reads exactly one byte, `volatile u16*` two.

```zark run
void main() {
    u32 word = 0xAABBCCDD;
    volatile u8* bytes = &word as *u8;
    volatile u16* halves = &word as *u16;
    println(bytes[0], bytes[1], halves[1]);
    bytes[1] = 0x11;
    println(word);
}
```

The real address of registers is given as a number through `as`: `auto uart = 0xFE201000 as *Uart;`.

## `packed struct`

An ordinary struct aligns its fields as in C. A `packed struct` puts the fields back to back, without gaps: this is how descriptors, IDT and GDT tables, packet headers and PCI configuration are laid out.

```zark run
packed struct Descriptor {
    u64 addr;
    u32 len;
    u16 flags;
    u16 next;
}

struct Loose { u8 tag; u32 len; u16 crc; }
packed struct Tight { u8 tag; u32 len; u16 crc; }

void main() {
    println(sizeof(Descriptor), sizeof(Loose), sizeof(Tight), alignof(Tight));
    Tight t;
    t.tag = 7;
    t.len = 0x01020304;
    t.crc = 0xABCD;
    volatile u8* raw = &t as *u8;
    println(raw[0], raw[1], raw[5], t.len, t.crc);
}
```

Access to unaligned fields is ordinary: x86-64 allows it. Aligning a struct type by hand is not supported yet (see `align(N)` for global variables below): align the buffers you need in the linker script.

## Register bits: `Bits`

```zark run
void main() {
    u64 reg = 0;
    reg = Bits::set(reg, 7, 4, 0xA);
    reg |= Bits::bit(0);
    println(reg, Bits::get(reg, 7, 4), Bits::mask(15, 8));
}
```

| Function | What it does |
|---|---|
| `Bits::bit(n)` | a number with the single bit `n` |
| `Bits::mask(hi, lo)` | a mask of the bits `hi..lo` inclusive |
| `Bits::get(v, hi, lo)` | the value of a bit field |
| `Bits::set(v, hi, lo, x)` | `v` with the field replaced |

The results have the type `u64`; for a 32-bit register add `as u32`: narrowing in Zark is always explicit.

## The processor: `Cpu`, and ports: `Port`

These are ordinary static methods. Privileged instructions crash in an ordinary program, so use them in a kernel or a driver.

| Function | Instruction |
|---|---|
| `Cpu::cli()`, `Cpu::sti()` | disable and enable interrupts |
| `Cpu::halt()`, `Cpu::pause()`, `Cpu::nop()`, `Cpu::breakpoint()` | `hlt`, `pause`, `nop`, `int3` |
| `Cpu::fence()`, `load_fence()`, `store_fence()` | `mfence`, `lfence`, `sfence` |
| `Cpu::rdtsc()` | the cycle counter |
| `Cpu::cr0()`, `cr2()`, `cr3()`, `cr4()` and `set_cr0(v)`, `set_cr3(v)`, `set_cr4(v)` | control registers |
| `Cpu::load_idt(p)`, `load_gdt(p)`, `invlpg(addr)` | `lidt`, `lgdt`, `invlpg` |
| `Cpu::rdmsr(n)`, `Cpu::wrmsr(n, v)` | model-specific registers |
| `Port::in8(p)`, `in16`, `in32` | `in` |
| `Port::out8(p, v)`, `out16`, `out32` | `out` |

`rdtsc`, `pause` and the barriers also work in ordinary programs:

```zark run
void main() {
    Cpu::fence();
    const auto a = Cpu::rdtsc();
    const auto b = Cpu::rdtsc();
    println(b >= a);
}
```

## `align(N)`: aligning a global variable

Page tables and DMA buffers must lie at an address that is a multiple of the page size. Write `align(N)` before a global variable; `N` is a power of two.

```zark run
align(4096) u64[512] page_table = 0;

void main() {
    println((&page_table[0] as u64) % 4096);
}
```

A struct type can be aligned too: `align(64) struct Line { u8 tag; i64 val; }` makes `alignof(Line)` and `sizeof(Line)` 64, and every variable, array element and field of that type is placed accordingly. The own backend handles locals aligned to 16; for more the compiler switches to LLVM by itself.

## Atomic operations and `Spinlock`

```zark run
void main() {
    u32 counter = 5;
    const auto old = Atomic::fetch_add32(&counter, 3);
    const auto prev = Atomic::swap32(&counter, 100);
    const auto seen = Atomic::cas32(&counter, 100, 7);
    println(old, prev, seen, counter);

    Spinlock lock;
    lock.lock();
    println(lock.try_lock());
    lock.unlock();
    println(lock.try_lock());
}
```

| Function | What it does |
|---|---|
| `Atomic::fetch_add32(p, v)`, `fetch_add8`, `fetch_add16`, `fetch_add64` | adds and returns the old value |
| `Atomic::swap32(p, v)`, `swap8`, `swap16`, `swap64` | writes and returns the old value |
| `Atomic::cas32(p, expected, desired)`, `cas8`, `cas16`, `cas64` | writes `desired` if `expected` is there; returns the previous value |

## `asm`: your own instructions

If the instruction you need is not in `Cpu`, you can insert it yourself: `asm<Type>("template", "constraints", operands...)`. The template and the constraints are in the LLVM (AT&T) syntax. Curly braces in the strings are escaped: `\{rax\}`.

```zark
u64 read_flags() { return asm<u64>("pushfq; popq $0", "=r,~\{memory\}"); }
```

The own backend encodes only the templates that the prelude uses (they are listed above). For the others it stops with a clear message, while a build with `--llvm` accepts any template.

## User-space drivers (Linux)

Most "drivers for reading memory and hardware" on Linux work without a kernel module: through `/dev/mem`, the PCI files in sysfs, `/dev/cpu/N/msr` and system calls. The prelude has everything for this, and libc is not needed: `Sys` calls the kernel directly with the `syscall` instruction, and errors are returned as `!T` (`error.PermissionDenied`, `error.NotFound`, `error.NoProcess`, `error.BadAddress`, `error.InvalidArgument`).

| What | How |
|---|---|
| a system call | `Sys::call(number, a1..a6)`, the wrappers `Sys::read`, `write`, `open`, `close`, `pread`, `pwrite`, `mmap`, `munmap`, `ioctl`, `getpid`, `slurp(a, path)` |
| page memory, device registers | `Mapping::anonymous(len)`, `Mapping::file(path, offset, len, write)`; `read8/16/32/64(off)`, `write8/16/32/64(off, v)`, `read_into(off, buffer)` |
| physical memory | `Mapping::file("/dev/mem", address, len, false)` (needs root, and the kernel may forbid ordinary memory) |
| another process | `Proc::read(pid, address, buffer)`, `Proc::write(pid, address, data)`, `Proc::maps(a, pid)` |
| PCI | `Pci::list(a)`, `Pci::config32(device, offset)`, `Pci::bar(device, n, write)` |
| MSR | `Msr::read(cpu, number)` (needs root and the `msr` module) |

Reads and writes through `Mapping` go through `volatile` and check the bounds: going past the page gives `error.OutOfRange`, not a crash.

```zark run
!void main() {
    auto page = Mapping::anonymous(4096)?;
    defer _ = page.unmap();
    page.write32(0, 0xCAFEBABE)?;
    println(page.read32(0)?, page.read16(2)?);
    println(page.read32(4094) catch 0);
}
```

Reading the memory of a process (your own, or one you have the right to by `ptrace_scope`):

```zark run
!void main() {
    u32[4] secret = [11, 22, 33, 44];
    u8[16] copy;
    const auto n = Proc::read(Sys::getpid(), &secret[0] as u64, copy[..])?;
    println(n, copy[0], copy[4], copy[8], copy[12]);
}
```

Listing the memory maps and finding a region:

```zark run
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto maps = Proc::maps(arena.allocator(), Sys::getpid())?;
    println(str_find(maps, "[stack]") >= 0);
}
```

PCI device identifiers (readable without root):

```zark
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    for (auto d : Pci::list(arena.allocator())?) {
        const auto id = Pci::config32(d, 0)?;
        println(d, "vendor {id & 0xFFFF:#x} device {id >> 16:#x}");
    }
}
```

Such programs build into one small executable. The usual permissions apply as always: access to `/dev/mem` and device BARs needs root, and other processes can be read only if `ptrace` allows it.

## Building without libc: `--freestanding`

`zark build kernel.zk boot.S -Wl,-T,linker.ld --freestanding -o kernel.elf` links with `-nostdlib -static` and turns off the bounds checks (their messages need libc). In this mode you can use everything that does not call libc: `Fmt` and `Writer` work without allocations, `println` is not needed because you write the output yourself.

The compiler may call `memset` and `memcpy` when copying and zeroing large values. In a kernel, define them yourself: a definition with `export` replaces the declaration from the prelude.

```zark
export void* memset(void* dst, i32 c, u64 n) {
    auto p = dst as *u8;
    for (auto i : 0..n) { p[i] = c as u8; }
    return dst;
}
```

The files `.S`, `.c`, `.o` and the parameters `-Wl,...`, `-T...`, `-nostdlib`, `-static` are passed as they are.

## An example: a kernel that boots in QEMU

`examples/baremetal/` holds a complete x86-64 kernel in Zark: `boot.S` (the Multiboot header, the switch to 64-bit mode, interrupt stubs), `linker.ld` and `kernel.zk`.

```zark
struct Serial {
    static void put(u8 c) {
        while ((Port::in8(0x3F8 + 5) & 0x20) == 0) { Cpu::pause(); }
        Port::out8(0x3F8, c);
    }
}

!void serial_write(void* ctx, str s) {
    for (auto c : s) { Serial::put(c); }
}

void kprintln(Fmt f) {
    auto w = Writer{ .ctx = null, .write_fn = serial_write };
    _ = w.put(f);
    Serial::put('\n');
}

export void kmain() {
    kprintln("Hello from Zark on bare metal!");
    kprintln("paging = {Bits::get(Cpu::cr0(), 31, 31)}");
}
```

Your own `kprintln` with string interpolation comes out of `Fmt` and `Writer` in six lines, and no memory is allocated. The kernel prints text to the serial port, builds an IDT (a `packed struct`), catches an `int3` exception in a handler written in Zark and returns from it. Running it:

```sh
$ examples/baremetal/run.sh
Hello from Zark on bare metal!
protected mode = 1, paging = 1
page table aligned = true, 4 * 5 = 20
fib = [0, 1, 1, 2, 3, 5, 8, 13]
interrupt 3, error code 0, back in the kernel
after int3
```

The script builds the kernel, turns the ELF into a 32-bit image for Multiboot (`objcopy -O elf32-i386`) and starts `qemu-system-x86_64`. The same example is checked by the tests on both backends.

## What is not there yet

- Linux kernel modules: they need the kernel headers (`linux-headers`), a third-party C file with `module_init` and a check in a virtual machine. The object file from `--freestanding` can be plugged into Kbuild, but there is no ready example yet.
- An `interrupt` attribute: interrupt handlers are written as assembly stubs (see `boot.S`) that call a Zark function.
- Bit fields in `struct`: use `Bits`.
- Encoding of arbitrary `asm` in the own backend.
- Targets other than x86-64.

## What next

- C and assembly files next to Zark: [interoperating with C](c-interop.md).
- Memory without a heap: [memory and allocators](memory.md).
- How the backends work: [how it all works](how-it-works.md).
