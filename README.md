# Vibe 🌊

**Self-hosted, with its own x86-64 backend.** The compiler is written in Vibe (`selfhost/`) and builds itself (see [BOOTSTRAP.md](BOOTSTRAP.md)). Debug builds use our own machine-code generator and ELF writer, with no LLVM involved; `--release` uses LLVM -O2.

| 10k-line program → executable | time |
|---|---|
| **vibe** (native backend) | **~95 ms** |
| clang -O0 | ~220 ms |
| gcc -O0 | ~670 ms |

(`bench/compile_speed.sh`; the same program is generated in both languages.)

A small systems language in the spirit of Zig, with less ceremony: native speed via LLVM, no hidden allocations (explicit `Allocator`), error unions with `?`, `defer`/`errdefer`, generics, tagged unions + `match`, function pointers, string interpolation without allocation, and direct C/C++ linking.

```vibe
struct Point { x: f64, y: f64 }

impl Point {
    fn len(self) f64 { return sqrt(self.x * self.x + self.y * self.y) }
}

fn div(a: i64, b: i64) !i64 {
    if b == 0 { return error.DivByZero }
    return a / b
}

fn main() !void {
    defer println("bye!")
    let p = Point{ x: 3.0, y: 4.0 }
    println("p = {p}, len = {p.len()}")      // p = Point{ x: 3, y: 4 }, len = 5

    let q = div(10, 2)?                       // propagate the error
    let r = div(1, 0) catch |e| { println("caught {e}"); -1 }

    var xs = List[i64].init(c_allocator())
    defer xs.deinit()
    for i in 0..5 { xs.push(i * i)? }
    println("xs = {xs.slice()}")              // xs = [0, 1, 4, 9, 16]
}
```

## Quick start

Requirements: clang (tested with clang 18), plus Zig 0.13 for stage0.

```sh
./bootstrap.sh                            # Zig stage0 -> self-hosted build/vibe (+ tests)
build/vibe run examples/hello.vibe
vibe build examples/bench.vibe --release -o bench
vibe run main.vibe lib.c engine.cpp       # link C/C++ sources directly
vibe ir  main.vibe                        # print LLVM IR
vibe test main.vibe                       # run the `test "name" { ... }` blocks
vibe fmt main.vibe                        # format in place (--check to only report)
VIBE=build/vibe tests/run.sh              # test suite
```

| Flag | Meaning |
|---|---|
| (default) | own x86-64 backend: fastest builds |
| `--llvm` | LLVM backend without optimizations |
| `--time` | print frontend/backend/link times |
| `-O` | LLVM `-O2`, bounds checks stay on |
| `--release` | `-O2` and bounds checks removed |
| `-o out` | output binary |
| `-- a b` | arguments for `vibe run` |

## How it differs from Zig

| | Zig | Vibe |
|---|---|---|
| Semicolons | required | optional (inserted at line ends, like Go) |
| Bindings | `const x: i32 = 5;` | `let x = 5` / `var x = 5` |
| Error propagation | `try f()` | `f()?` |
| Value from `catch` block | `blk: { ... break :blk v; }` | `catch \|e\| { log(e); -1 }` (last expression is the value) |
| Generics | `fn max(comptime T: type, a: T, b: T) T` | `fn max[T](a: T, b: T) T`, with T inferred at the call |
| Generic types | function returning `type` | `struct List[T] { ... }` + `impl List[T] { ... }` |
| Methods | `self: *Self` everywhere | bare `self` means `self: *Self` |
| Printing | `std.debug.print("{d}\n", .{x})` | `println("x = {x}")`, which prints any type, structs included |
| String interpolation | none | `println("sum = {a + b}")`, `bprint(buf, ...)`, never allocates |
| C | `@cImport` | `extern fn` + pass `.c/.cpp` files to the compiler |
| Ignored error unions | compile error | compile error (kept) |

## Language tour

**Types:** `i8..i64`, `u8..u64`, `isize/usize`, `f32/f64`, `bool`, `str` (equivalent to `[]u8`), `*T`, `[]T`, `[N]T`, `!T`, structs, enums, generic structs.

**Variables:** `let` is an immutable binding, `var` is mutable. Integer literals take their type from context and default to `i64`. Ints widen implicitly when it is lossless. Anything else needs `as`.

**Control flow:** `if/else`, `while`, `for i in 0..n`, `for x in slice`, `for i, x in list`, `break/continue`, and `match`:

```vibe
match dir {
    .North => println("up")
    .East, .West => println("sideways")
    _ => {}
}
```

`match` works on integers, enums and strings.

**Errors:** a function returns `!T` and uses `return error.Name`. Callers use `expr?` to propagate or `expr catch default` / `catch |e| { ... }` to handle. When `main` returns `!void`, an unhandled error prints `error: Name` and exits with code 1.

**defer / errdefer:** these run at scope exit, including on `return`, `break` and `continue`. `errdefer` runs only on error paths.

**Comptime (lite):** `const N = 4 * 2` is evaluated at compile time. It works in array sizes `[N]i32` and with `sizeof(T)`. Generics are monomorphized, and only reachable code gets compiled (lazy analysis, like Zig).

**Safety:** bounds checks on arrays and slices (`panic: index 3 out of bounds (len 3) at file:line`), plus `assert(cond)` and `panic("msg {x}")`.

**Pointers:** `&x`, `*p`, `p[i]` (pointer arithmetic), `p + n`, auto-deref for fields (`p.x`), slicing `p[a..b]` and `s[a..]`. `*u8` acts like `void*` and converts to and from any pointer.

### C / C++ interop

```vibe
extern fn c_gcd(a: i64, b: i64) i64            // call C
export fn vibe_square(x: i64) i64 { return x * x }  // C calls Vibe under its own name
struct Vec3 { x: f64, y: f64, z: f64 }         // C-compatible layout
extern fn vec3_dot(a: *Vec3, b: *Vec3) f64
```
`vibe run main.vibe mathlib.c engine.cpp` compiles everything and links with `clang++` automatically. C++ is reached through an `extern "C"` facade: see `examples/interop/`. String literals pass as `const char*` directly.

## Memory: no hidden allocations

```vibe
var mem: [1024]u8
var fb = FixedBuf.init(mem[..])       // bump allocator over a stack buffer, no heap
var xs = List[i32].init(fb.allocator())
xs.push(42)?                          // out of memory is an ordinary error
var line: [64]u8
let s = bprint(line[..], "n = {xs.len}")?   // formatting into your own buffer
```

## Standard library (auto-imported prelude, `src/std.vibe`)

- `Allocator` (ctx + 2 function pointers), `c_allocator()`, `FixedBuf`: `alloc[T], free, create[T], destroy, dup`
- `List[T]`: `init(a), deinit, reserve, push, append, pop, last, get, set, slice, sort, reverse, contains, clear`
- `Map[V]`: str → V, `init(a), deinit, put (!void), get (!V), has`
- `Option[T]`: `union { Some: T, None }` with `is_some`, `unwrap_or`
- `sort[T](slice)`, `min, max, abs, swap`, strings: `str_find, str_trim, str_starts_with, str_ends_with, parse_int, cstr, read_line(buf)`
- `Arena`; files: `read_file, write_file, file_exists`; processes: `run(a, argv)`, `env`; `to_cstr`, `parse_int_radix`, `parse_float`
- math, `clock()`, `arg_count()/arg(i)`; any libc function through `extern fn`

The full language description is in [SPEC.md](SPEC.md).

## Performance

`examples/bench.vibe` (recursive fib(38) + a sieve up to 50M), clang 18, `--release`:

| | fib(38) | sieve 50M |
|---|---|---|
| C (`clang -O2`) | 97 ms | 369 ms |
| Vibe (`--release`) | 95 ms | 345 ms |

The full build of the example, compilation plus linking, takes about 80 ms.

## Compiler architecture

The self-hosted compiler lives in `selfhost/` (~4.5k lines of Vibe, see BOOTSTRAP.md). The original Zig compiler in `src/` (~4.5k lines) is kept as stage0:

```
src/lexer.zig    tokens + automatic `;` at line ends
src/parser.zig   recursive descent → AST; string interpolation parsed into sub-expressions
src/codegen.zig  type checking + monomorphization + LLVM IR (text), one pass
src/main.zig     driver: imports, IR → clang, linking .c/.cpp/.o
src/std.vibe     prelude written in Vibe itself (List, Map, StrBuf, runtime helpers)
```
The compiler emits textual LLVM IR and calls `clang`, with no linking against libLLVM. Locals become `alloca`s, which LLVM promotes to registers at `-O2`.

## Roadmap

- [x] v0.2: no hidden allocations, `Allocator`, `*void`, function pointers, tagged unions, `..` in literals, `alignof`, errdefer on runtime errors
- [x] v0.3: files, processes, `sprint`, format specs, `type` aliases, `Arena`; self-hosted lexer identical to the Zig one
- [x] **v0.5: own x86-64 backend + ELF writer** (default); the native-built compiler reaches its own fixed point. Next steps: [ROADMAP.md](ROADMAP.md)
- [x] **v0.4: self-hosted.** The compiler is written in Vibe and reaches a fixed point (stage2 == stage3); adds `is`, `eprint`, `embed`
- [ ] `comptime` blocks, `inline for`
- [ ] `@cImport` via libclang; passing structs by value across the C ABI
- [x] closures (explicit captures, context on the stack), `match` as an expression, `?T`/`orelse`, `import as`, `T: Ord` constraints, `vibe test`, `vibe fmt`
