# Zark

> **Pre-release 0.6.0-pre.** The ownership rules for resource elements changed (a runtime index and a `for` no longer produce a second owner); see [CHANGELOG.md](CHANGELOG.md). The checks and the standard library may still change before 0.6.0.

**Self-hosted, with its own x86-64 backend.** The compiler is written in Zark (`selfhost/`) and builds itself (see [BOOTSTRAP.md](BOOTSTRAP.md)). Debug builds use our own machine-code generator and ELF writer, with no LLVM involved; `--release` uses LLVM -O2.

| 10k-line program → executable | time |
|---|---|
| **zark** (native backend, safe mode) | **~200 ms** |
| zark, `--no-safety` | ~135 ms |
| clang -O0 | ~315 ms |
| gcc -O0 | ~710 ms |

(`bench/compile_speed.sh`; the same program is generated in both languages.)

A small systems language in the spirit of Zig, with less ceremony: native speed via LLVM, no hidden allocations (explicit `Allocator`), error unions with `?`, `defer`/`errdefer`, generics, tagged unions + `match`, function pointers, string interpolation without allocation, and direct C/C++ linking.

> **Status: alpha.** Zark is pre-1.0: the language, the standard library and
> `zark.toml` can change between releases. The native backend targets Linux
> x86-64; macOS, arm64 and Windows/WSL use the LLVM path. C/C++ bindings
> (`import "x.h"`, `zark cbind`) and the package manager are experimental.

```zark
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

Requirements: clang 18 or newer (tested with 18, 19 and 22). Builds on Linux (glibc and musl, x86-64 and arm64), macOS and Windows through WSL2: see [INSTALL.md](INSTALL.md) ([по-русски](INSTALL.ru.md)).

```sh
./bootstrap.sh                            # seed -> self-hosted build/zark (+ tests)
build/zark run examples/hello.zk
zark build examples/bench.zk --release -o bench
zark run main.zk lib.c engine.cpp       # link C/C++ sources directly
zark ir  main.zk                        # print LLVM IR
zark test main.zk                       # run the `test "name" { ... }` blocks
zark fmt main.zk                        # format in place (--check to only report)
zark new app && cd app && zark run        # a project with zark.toml
ZARK=build/zark tests/run.sh              # test suite
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
| `-- a b` | arguments for `zark run` |

The native backend compiles functions on several threads (up to 8, one per CPU). `ZARK_JOBS=1` forces one thread, `ZARK_JOBS=N` sets the count; the output is the same byte for byte.

## Documentation

The guide is in [`docs/index.html`](docs/index.html): open it in a browser, or serve the
directory (`python3 -m http.server -d docs`). It is generated from the Markdown in
`docs-src/pages/` (the Russian translation is `docs-src/pages-ru/`), and every code block
in it was compiled and run by the real compiler when the site was built.

| If you want to… | Read |
|---|---|
| install and build | [INSTALL.md](INSTALL.md), [installation and the first program](docs/getting-started.html) |
| learn the language | [Learn Zark](docs/learn.html) (a course), [quick tour](docs/tour.html) |
| look up a feature | [types](docs/types.html), [errors and optionals](docs/errors-and-optionals.html), [memory](docs/memory.html), [strings](docs/strings.html), [collections](docs/collections.html) |
| call C or C++ | [C interop](docs/c-interop.html), [C++ style](docs/cpp-style.html), [SPEC.md section 8](SPEC.md) |
| run I/O concurrently | [async](docs/async.html) (futures, join, select, cancellation) |
| write a real program | [cookbook](docs/cookbook.html), [showcase](docs/showcase.html) (a threaded ray tracer) |
| use the tools | [testing](docs/testing.html), [tooling](docs/tooling.html), [debugging](docs/debugging.html) |
| understand the compiler | [how it works](docs/how-it-works.html), [BOOTSTRAP.md](BOOTSTRAP.md) |
| know the fine print | [SPEC.md](SPEC.md) (the normative reference), [safety model](docs/safety.html), [pitfalls](docs/gotchas.html) |
| contribute | [CONTRIBUTING.md](CONTRIBUTING.md) |

The [SPEC.md](SPEC.md) is the normative description of the language. Sections 11 and 12
list what the compiler does **not** check and which behaviour is undefined or
implementation-defined, so read them before relying on a guarantee.

## Editor support

`zark lsp` is a language server over stdio, built on the compiler frontend: compiler errors as you type (also in unsaved buffers), hover, completion (members, modules, enum variants, struct literal fields, types), signature help, go to definition (also into imported files), references and rename across the workspace, outline, workspace symbols, highlights, format, and quick fixes for "did you mean". Any LSP client can use it.

`editors/vscode` is a VS Code / code-oss extension: syntax highlighting (declarations, types, enum/union variants, fields, namespaces, string interpolation and format specs, modifiers, `error.X`), snippets, the language server (diagnostics, completion, hover, signature help, definition, references, rename, outline, formatting and quick fixes), and Run/Test/Build/Format commands with CodeLens and a status bar. Build and install it in one step:

```sh
editors/vscode/install.sh
```

or manually: `cd editors/vscode && npm ci && python3 pack.py && code --install-extension zark-lang-0.3.0.vsix`. The extension finds `build/zark` in the workspace, `zark` on `PATH`, `~/.local/bin/zark`, and the usual install directories; `zark.path` overrides that. See [editors/vscode/README.md](editors/vscode/README.md) for settings and keybindings.

## How it differs from Zig

| | Zig | Zark |
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

```zark
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

```zark
extern i64 c_gcd(i64 a, i64 b);            // call C
export i64 zark_square(i64 x) { return x * x; }  // C calls Zark under its own name
struct Vec3 { f64 x; f64 y; f64 z; }         // C-compatible layout
extern f64 vec3_dot(Vec3* a, Vec3* b);
```
`zark run main.zk mathlib.c engine.cpp` compiles everything and links with `clang++` automatically. C++ can also be reached through an `extern "C"` facade: see `examples/interop/`. String literals pass as `const char*` directly.

C headers need no hand-written declarations: `import "SDL2/SDL.h" as sdl;` binds the functions, structs, unions, enums, constant macros and static inline functions of a header (`zark cbind header.h` prints the same bindings as a file). A `zark.toml` sets include directories, defines, the C/C++ standard, `pkg-config` packages and the C/C++ sources; objects are cached by content and compiled in parallel. `examples/imgui/` drives Dear ImGui and SDL2 this way. C++ headers (`.hpp`) are imported the same way: classes, methods, overloads, templates and `std::string`/`std::vector`/`std::unique_ptr` are bound through generated C++ shims (SPEC.md section 8). An extern variable `int count;` becomes `count_ptr()`, which returns its address; a struct with bitfields gets `get_f()`/`set_f(v)`; a struct aligned above 8 becomes `align(N) struct`; a plain `char` is `i8` where C's `char` is signed and `u8` where it is unsigned (Linux arm64).

Structs and Zark unions go by value through `extern`, `export` and function pointers (a union is `{ int32_t tag; payload }` to C, the tag being the zero-based variant index), and variadic C functions take structs and unions as C passes them. The C ABIs are System V x86-64 and AAPCS64 on Linux and Apple arm64; arm64 builds always use the LLVM path, since the native backend is x86-64 only. SIMD vectors cross as C vectors of 16 bytes (also 8 bytes on arm64), not inside structs. Details and limits are in SPEC.md section 8.

## Drivers and bare metal

`volatile` registers and fields, `packed struct`, `Port`, `Cpu`, `Bits`, `Atomic` and `Spinlock` in the prelude, inline `asm<T>("...", "...", args)`, and `--freestanding` builds without libc. The same code runs on the native and the LLVM backend. `examples/baremetal/` is an x86-64 kernel written in Zark that boots in QEMU (`examples/baremetal/run.sh`): serial output through `Fmt`, an IDT built from a `packed struct`, an exception handled in Zark.

```zark
packed struct Descriptor { u64 addr; u32 len; u16 flags; u16 next; }
struct Uart { volatile u32 data; volatile u32 status; }

void send(Uart* u, u8 byte) {
    while ((u.status & 1) == 0) { Cpu::pause(); }
    u.data = byte;
}
```

## Memory: no hidden allocations

```zark
u8[1024] mem;
auto fb = FixedBuf::init(mem[..]);       // bump allocator over a stack buffer, no heap
auto xs = List<i32>::init(fb.allocator());
xs.push(42)?;                          // out of memory is an ordinary error
u8[64] line;
const auto s = bprint(line[..], "n = {xs.len}")?;   // formatting into your own buffer
```

## Standard library (auto-imported prelude, `std/std.zk`)

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

`std/fs` (directories, walking, copying), `std/path`, `std/time` (`DateTime`, ISO 8601, `Stopwatch`), `std/os` (run programs and capture output, environment), `std/args` (command-line options), `std/json` (parse with error positions, build, print), `std/net` (TCP), `std/http` (client and server), `std/thread` (threads, `Mutex`, `Channel<T>`), `std/async` (a single-threaded executor with timers and TCP on epoll or kqueue). See the guide page "Standard modules".

A file that starts with `#!/usr/bin/env -S zark run` can be run directly as a script; the arguments after it go to the program.

### Async

`async` functions compile to state machines. Calling one returns its frame by value, so its size is known (`sizeof(f)`) and you decide where it lives; nothing is allocated. `await` suspends the function until the awaited future is ready. A future is any struct with `Poll<T> poll(Context* cx)`, and `std/async` runs them with an `Executor` (`block_on`, `spawn`, `Sleep`, `TcpListener`, `TcpStream`).

```zark
async i64 add(i64 a, i64 b) { return a + b; }

async i64 chain() {
    auto x = await add(1, 2);
    auto y = await add(x, 10);
    return x * y;
}
```

`await` is only allowed where nothing else is half-evaluated (a statement, an initializer, `v = await f();`, `return await f();`, an `if`/`while`/`match` condition), and the ownership checks apply across it. See SPEC.md section 7b. `examples/async_echo.zk` is an echo server written with `async`/`await`: a server task spawns one task per accepted connection, and three clients collect their replies through `JoinHandle`s. `tests/edge/async_basic.zk` shows more of the syntax.

### Projects

`zark new hello` creates a project with a `zark.toml`; inside it `zark run`, `zark build` and `zark test` need no file name. The manifest lists C sources, libraries, default flags, and dependencies by path or git (`utils = { path = "../utils" }`, then `import "utils" as u;`).

The full language description is in [SPEC.md](SPEC.md).

## Performance

`examples/bench.zk` (recursive fib(38) + a sieve up to 50M), clang 18, on one machine
(`bench/runtime.sh` also compares the own backend, `--native --release` and gcc/clang):

| | fib(38) | sieve 50M |
|---|---|---|
| C (`clang -O2`) | 90 ms | 560 ms |
| Zark (`--release`, no checks) | 100 ms | 575 ms |
| Zark (`-O`, all safety checks on) | 170 ms | 540 ms |
| C (`clang -O0`) | 250 ms | 780 ms |
| Zark, own backend (safe mode) | 360 ms | 1210 ms |

The full build of the example, compilation plus linking, takes about 80 ms.

## Compiler architecture

The self-hosted compiler lives in `selfhost/` (see BOOTSTRAP.md). It is built from a committed seed (`bootstrap/seed.ll.gz`), so only clang is needed:

```
selfhost/lexer.zk    tokens
selfhost/parser.zk   recursive descent → AST; string interpolation parsed into sub-expressions
selfhost/gen*.zk     type checking + monomorphization + LLVM IR (text), one pass
selfhost/native.zk   own x86-64 backend, x64.zk encoder + ELF writer
selfhost/main.zk     driver: imports, IR → backend, linking .c/.cpp/.o
std/std.zk           prelude written in Zark itself (List, Map, Arena, runtime helpers)
```
The compiler emits textual LLVM IR and calls `clang`, with no linking against libLLVM. Locals become `alloca`s, which LLVM promotes to registers at `-O2`.

### Repository layout

| Path | What is there |
|---|---|
| `selfhost/` | the compiler, written in Zark (lexer, parser, type checker, LLVM IR, native x86-64 backend, driver) |
| `std/` | the prelude (`std.zk`) and the standard modules (`fs`, `path`, `json`, `net`, `http`, `thread`, `async`, …) |
| `bootstrap/seed.ll.gz` | the compiler's own LLVM IR, the starting point of the bootstrap (see [BOOTSTRAP.md](BOOTSTRAP.md)) |
| `tests/` | the test suite: golden outputs, edge cases, pinned error messages, C/C++ binding tests, ABI and fuzz drivers |
| `tools/` | fuzzers, the ASan/UBSan build (`build_asan.sh`), and `update-seed.sh` |
| `examples/` | runnable programs: `hello.zk`, `bench.zk`, the ImGui UI, the bare-metal kernel, C/C++ interop |
| `docs-src/`, `docs/` | the guide's Markdown sources and the generated HTML |
| `editors/vscode/` | the VS Code extension (highlighting, snippets, run/test buttons) |
| `bench/` | the compile-speed comparison |
| `legacy/zig-stage0/` | the retired Zig compiler, kept for history only |

## Testing

The suite is one script; it runs the compiler on every test and compares the result with
the expected output:

```sh
ZARK=build/zark tests/run.sh            # the default (native) backend
ZARK=build/zark tests/run.sh --llvm     # the LLVM backend without optimizations
ZARK=build/zark tests/run.sh -O         # LLVM -O2, bounds checks still on
```

It covers: the examples and their expected stdout, golden token streams, edge cases
(`tests/edge`), diagnostics pinned to the first line of every `tests/errors/*.zk` (the
`.err` files), panics, the crash handler's backtrace, the C and C++ binders
(`tests/cbind.sh`, `tests/cxxbind.sh`), the C ABI fuzzer, the standard-module tests,
formatter idempotence (`tests/fmt_idem.sh`), IR determinism (`tests/determinism.sh`),
every code block in the guide (`tests/docs.sh`) and a compile-time budget for the
self-hosted compiler (`tests/scale.sh`). The quick passes of the four fuzzers also run
from `tests/run.sh`; the full runs are in `tools/`:

```sh
python3 tools/fuzz_prog.py --count 10000    # random programs against a reference model
python3 tools/fuzz_crash.py --count 100000  # mutations: no crash, no hang
python3 tools/fuzz_lsp.py --count 2000      # JSON-RPC sessions
python3 tools/fuzz_own.py --count 300       # ownership: no false errors, no accepted mistakes
tools/build_asan.sh                     # build/zark-asan (AddressSanitizer + UBSan)
ZARK=build/zark-asan tests/run.sh       # the suite under the sanitizers
```

`bootstrap.sh` runs `tests/run.sh` with the compiler it just built, so a broken fixed
point or a failed test stops the build before `build/zark` is installed.

## Roadmap

- [x] v0.2: no hidden allocations, `Allocator`, `*void`, function pointers, tagged unions, `..` in literals, `alignof`, errdefer on runtime errors
- [x] v0.3: files, processes, `sprint`, format specs, `type` aliases, `Arena`; self-hosted lexer
- [x] **v0.4: self-hosted.** The compiler is written in Zark and reaches a fixed point (stage2 == stage3); adds `is`, `eprint`, `embed`
- [x] **v0.5: own x86-64 backend + ELF writer** (default); the native-built compiler reaches its own fixed point. Next steps: [ROADMAP.md](ROADMAP.md)
- [ ] **v0.6.0-pre: soundness release.** A resource element cannot be copied by a runtime index (#78) or moved/mutated out of a `for` (#58); `List.pop/remove_at/swap_remove/take/clear` are `invalidates`; `move_out` is the explicit escape; errors inside a generic name it. Both fixed points and the seed reproduce byte for byte.
- [ ] `comptime` blocks, `inline for`
- [x] passing structs by value across the C ABI (`extern`)
- [ ] `@cImport` via libclang
- [x] `async`/`await` as state machines with a single-threaded executor (`std/async`); a multi-threaded executor and `join`/`select` are not done
- [x] closures (explicit captures, context on the stack), `match` as an expression, `?T`/`orelse`, `import as`, `T: Ord` constraints, `zark test`, `zark fmt`

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([LICENSE-MIT](LICENSE-MIT))

at your option.

Unless you explicitly state otherwise, any contribution intentionally
submitted for inclusion in Zark by you, as defined in the Apache-2.0
license, shall be dual licensed as above, without any additional terms or
conditions.
