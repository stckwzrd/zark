# Vibe 🌊

**Self-hosted, with its own x86-64 backend.** The compiler is written in Vibe (`selfhost/`) and builds itself (see [BOOTSTRAP.md](BOOTSTRAP.md)). Debug builds use our own machine-code generator and ELF writer, with no LLVM involved; `--release` uses LLVM -O2.

| 10k-line program → executable | time |
|---|---|
| **vibe** (native backend, safe mode) | **~200 ms** |
| vibe, `--no-safety` | ~135 ms |
| clang -O0 | ~315 ms |
| gcc -O0 | ~710 ms |

(`bench/compile_speed.sh`; the same program is generated in both languages.)

A small systems language in the spirit of Zig, with less ceremony: native speed via LLVM, no hidden allocations (explicit `Allocator`), error unions with `?`, `defer`/`errdefer`, generics, tagged unions + `match`, function pointers, string interpolation without allocation, and direct C/C++ linking.

```vibe
struct Point {
    f64 x;
    f64 y;

    f64 len() { return sqrt(x * x + y * y); }
}

!i64 div(i64 a, i64 b) {
    if (b == 0) { return error.DivByZero; }
    return a / b;
}

!void main() {
    defer println("bye!");
    const auto p = Point{ .x = 3.0, .y = 4.0 };
    println("p = {p}, len = {p.len()}");      // p = Point{ x: 3, y: 4 }, len = 5

    const auto q = div(10, 2)?;               // propagate the error
    const auto r = div(1, 0) catch |e| { println("caught {e}"); -1 };

    auto xs = List<i64>::init(c_allocator());
    defer xs.deinit();
    for (auto i : 0..5) { xs.push(i * i)?; }
    println("xs = {xs.slice()}");              // xs = [0, 1, 4, 9, 16]
}
```

## Quick start

Requirements: clang (tested with clang 18). Builds on Linux (glibc and musl, x86-64 and arm64), macOS and Windows through WSL2: see [INSTALL.md](INSTALL.md) ([по-русски](INSTALL.ru.md)).

```sh
./bootstrap.sh                            # seed -> self-hosted build/vibe (+ tests)
build/vibe run examples/hello.vibe
vibe build examples/bench.vibe --release -o bench
vibe run main.vibe lib.c engine.cpp       # link C/C++ sources directly
vibe ir  main.vibe                        # print LLVM IR
vibe test main.vibe                       # run the `test "name" { ... }` blocks
vibe fmt main.vibe                        # format in place (--check to only report)
vibe new app && cd app && vibe run        # a project with vibe.toml
VIBE=build/vibe tests/run.sh              # test suite
```

| Flag | Meaning |
|---|---|
| (default) | own x86-64 backend: fastest builds (x86-64 Linux; other systems use LLVM) |
| `--llvm` | LLVM backend without optimizations |
| `--time` | print frontend/backend/link times |
| `-O` | LLVM `-O2`, bounds checks stay on |
| `--release` | `-O2` and bounds checks removed |
| `--fast-math` | `--fast` plus fast-math flags on float arithmetic (reassociation, like `-ffast-math`) |
| `-g` | own backend: keep locals in memory and describe them for gdb (`print x`, `info locals`) |
| `--check-overflow` | checks `+`, `-` and `*` for overflow even with `--release` (a safe build always checks your code; the prelude is not checked) |
| `--fast` | `--release` plus `nsw` on signed arithmetic (signed overflow is undefined, as in C++) |
| `-o out` | output binary |
| `-- a b` | arguments for `vibe run` |

## Editor support

`vibe lsp` is a language server over stdio, built on the compiler frontend: compiler errors as you type (also in unsaved buffers), hover, completion (members, modules, enum variants, struct literal fields, types), signature help, go to definition (also into imported files), references and rename across the workspace, outline, workspace symbols, highlights, format, and quick fixes for "did you mean". Any LSP client can use it.

`editors/vscode` is a VS Code / code-oss extension that starts the server and adds highlighting, snippets and run/test buttons. Build and install it with `cd editors/vscode && npm install && python3 pack.py out.vsix && code-oss --install-extension out.vsix`. It calls `vibe` from `PATH` (or `~/.local/bin/vibe`); change that with the `vibe.path` setting.

## How it differs from Zig

| | Zig | Vibe |
|---|---|---|
| Declarations | `const x: i32 = 5;` | `const i32 x = 5;`, C++-style: type first, `auto`, mutable by default |
| Error propagation | `try f()` | `f()?` |
| Value from `catch` block | `blk: { ... break :blk v; }` | `catch \|e\| { log(e); -1 }` (last expression is the value) |
| Generics | `fn max(comptime T: type, a: T, b: T) T` | `template<T> T max(T a, T b)`, with T inferred at the call |
| Generic types | function returning `type` | `struct List<T> { ... }` |
| Methods | `self: *Self` everywhere | declared inside the `struct`, `this` is the pointer, fields by bare name |
| Printing | `std.debug.print("{d}\n", .{x})` | `println("x = {x}")`, which prints any type, structs included |
| String interpolation | none | `println("sum = {a + b}")`, `bprint(buf, ...)`, never allocates |
| C | `@cImport` | `extern` + pass `.c/.cpp` files to the compiler |
| Ignored error unions | compile error | compile error (kept) |

## Language tour

**Types:** `i8..i64`, `u8..u64`, `isize/usize`, `f32/f64`, `bool`, `str` (equivalent to `u8[]`), `T*`, `T[]`, `T[N]`, `!T`, structs, enums, generic structs.

**Variables:** `T x = ...;` or `auto x = ...;`, mutable by default, `const` makes them immutable. Integer literals take their type from context and default to `i64`. Ints widen implicitly when it is lossless. Anything else needs `as`.

**Control flow:** `if/else`, `while`, `for (auto i : 0..n)`, `for (auto x : slice)`, `for (auto [i, x] : list)`, `break/continue`, and `match`:

```vibe
match dir {
    .North => println("up");
    .East, .West => println("sideways");
    _ => {}
}
```

`match` works on integers, enums and strings.

**Errors:** a function returns `!T` and uses `return error.Name`. Callers use `expr?` to propagate or `expr catch default` / `catch |e| { ... }` to handle. When `main` returns `!void`, an unhandled error prints `error: Name` and exits with code 1.

**defer / errdefer:** these run at scope exit, including on `return`, `break` and `continue`. `errdefer` runs only on error paths.

**Comptime (lite):** `const auto N = 4 * 2;` is evaluated at compile time. It works in array sizes `i32[N]` and with `sizeof(T)`. Generics are monomorphized, and only reachable code gets compiled (lazy analysis, like Zig).

**Safety:** bounds checks on arrays and slices (`panic: index 3 out of bounds (len 3) at file:line`), plus `assert(cond)` and `panic("msg {x}")`.

**Pointers:** `&x`, `*p`, `p[i]` (pointer arithmetic), `p + n`, auto-deref for fields (`p.x`), slicing `p[a..b]` and `s[a..]`. `void*` converts to and from any pointer.

### C / C++ interop

```vibe
extern i64 c_gcd(i64 a, i64 b);            // call C
export i64 vibe_square(i64 x) { return x * x; }  // C calls Vibe under its own name
struct Vec3 { f64 x; f64 y; f64 z; }         // C-compatible layout
extern f64 vec3_dot(Vec3* a, Vec3* b);
```
`vibe run main.vibe mathlib.c engine.cpp` compiles everything and links with `clang++` automatically. C++ is reached through an `extern "C"` facade: see `examples/interop/`. String literals pass as `const char*` directly.

## Drivers and bare metal

`volatile` registers and fields, `packed struct`, `Port`, `Cpu`, `Bits`, `Atomic` and `Spinlock` in the prelude, inline `asm<T>("...", "...", args)`, and `--freestanding` builds without libc. The same code runs on the native and the LLVM backend. `examples/baremetal/` is an x86-64 kernel written in Vibe that boots in QEMU (`examples/baremetal/run.sh`): serial output through `Fmt`, an IDT built from a `packed struct`, an exception handled in Vibe.

```vibe
packed struct Descriptor { u64 addr; u32 len; u16 flags; u16 next; }
struct Uart { volatile u32 data; volatile u32 status; }

void send(Uart* u, u8 byte) {
    while ((u.status & 1) == 0) { Cpu::pause(); }
    u.data = byte;
}
```

## Memory: no hidden allocations

```vibe
u8[1024] mem;
auto fb = FixedBuf::init(mem[..]);       // bump allocator over a stack buffer, no heap
auto xs = List<i32>::init(fb.allocator());
xs.push(42)?;                          // out of memory is an ordinary error
u8[64] line;
const auto s = bprint(line[..], "n = {xs.len}")?;   // formatting into your own buffer
```

## Standard library (auto-imported prelude, `std/std.vibe`)

- `Allocator` (ctx + 2 function pointers), `c_allocator()`, `FixedBuf`: `alloc<T>, free, create<T>, destroy, dup`
- `List<T>`: `init(a), deinit, reserve, push, append, pop, last, get, set, slice, sort, reverse, contains, clear`
- `Map<V>`: str → V, `init(a), deinit, put (!void), get (!V), has`
- `Option<T>`: `union { T Some; None; }` with `is_some`, `unwrap_or`
- `sort(slice)`, `min, max, abs, swap`, strings: `str_find, str_trim, str_starts_with, str_ends_with, parse_int, cstr, read_line(buf)`
- `Arena`; files: `read_file, write_file, file_exists`; processes: `run(a, argv)`, `env`; `to_cstr`, `parse_int_radix`, `parse_float`
- math, `clock()`, `arg_count()/arg(i)`; any libc function through `extern`
- `HashMap<K, V>` / `HashSet<T>` for any printable key type, `str_split`, `str_join`, `str_replace`, UTF-8, `sort_by`
- `DebugAllocator`: finds leaks, use after free, overflows and double frees; crashes print the cause and a backtrace with source lines

### Standard modules (`import "std/fs" as fs;`)

`std/fs` (directories, walking, copying), `std/path`, `std/time` (`DateTime`, ISO 8601, `Stopwatch`), `std/os` (run programs and capture output, environment), `std/args` (command-line options), `std/json` (parse with error positions, build, print), `std/net` (TCP), `std/http` (client and server), `std/thread` (threads, `Mutex`, `Channel<T>`). See the guide page "Standard modules".

A file that starts with `#!/usr/bin/env -S vibe run` can be run directly as a script; the arguments after it go to the program.

### Projects

`vibe new hello` creates a project with a `vibe.toml`; inside it `vibe run`, `vibe build` and `vibe test` need no file name. The manifest lists C sources, libraries, default flags, and dependencies by path or git (`utils = { path = "../utils" }`, then `import "utils" as u;`).

The full language description is in [SPEC.md](SPEC.md).

## Performance

`examples/bench.vibe` (recursive fib(38) + a sieve up to 50M), clang 18, on one machine:

| | fib(38) | sieve 50M |
|---|---|---|
| C (`clang -O2`) | 90 ms | 560 ms |
| Vibe (`--release`, no checks) | 100 ms | 575 ms |
| Vibe (`-O`, all safety checks on) | 170 ms | 540 ms |
| C (`clang -O0`) | 250 ms | 780 ms |
| Vibe, own backend (safe mode) | 360 ms | 1210 ms |

The full build of the example, compilation plus linking, takes about 80 ms.

## Compiler architecture

The self-hosted compiler lives in `selfhost/` (see BOOTSTRAP.md). It is built from a committed seed (`bootstrap/seed.ll.gz`), so only clang is needed:

```
selfhost/lexer.vibe    tokens
selfhost/parser.vibe   recursive descent → AST; string interpolation parsed into sub-expressions
selfhost/gen*.vibe     type checking + monomorphization + LLVM IR (text), one pass
selfhost/native.vibe   own x86-64 backend, x64.vibe encoder + ELF writer
selfhost/main.vibe     driver: imports, IR → backend, linking .c/.cpp/.o
std/std.vibe           prelude written in Vibe itself (List, Map, Arena, runtime helpers)
```
The compiler emits textual LLVM IR and calls `clang`, with no linking against libLLVM. Locals become `alloca`s, which LLVM promotes to registers at `-O2`.

## Roadmap

- [x] v0.2: no hidden allocations, `Allocator`, `*void`, function pointers, tagged unions, `..` in literals, `alignof`, errdefer on runtime errors
- [x] v0.3: files, processes, `sprint`, format specs, `type` aliases, `Arena`; self-hosted lexer
- [x] **v0.5: own x86-64 backend + ELF writer** (default); the native-built compiler reaches its own fixed point. Next steps: [ROADMAP.md](ROADMAP.md)
- [x] **v0.4: self-hosted.** The compiler is written in Vibe and reaches a fixed point (stage2 == stage3); adds `is`, `eprint`, `embed`
- [ ] `comptime` blocks, `inline for`
- [x] passing structs by value across the C ABI (`extern`)
- [ ] `@cImport` via libclang
- [x] closures (explicit captures, context on the stack), `match` as an expression, `?T`/`orelse`, `import as`, `T: Ord` constraints, `vibe test`, `vibe fmt`
