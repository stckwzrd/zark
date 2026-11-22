# Zark: "no magic in the compiler" redesign

This file is the resume point. Work top to bottom; continue from the first unchecked item.

## Goal

The compiler stops knowing standard-library names and is split into layers: `parse -> sema (typed AST) -> lowering -> backends`. Everything else (`print`, formatting, `List`, `Map`, allocators, `sort`) is ordinary Zark code in the std. Zark stays clearer than Zig (no `anytype`, no implicit comptime) and fast: no phase of compile time may regress by more than 10%.

## Baseline (recorded before Phase 1)

- Tests: 21/21 (`tests/run.sh`), fixed points stage2 == stage3 and native2 == native3.
- Compile time (min of 7-12 runs on a noisy machine, `build/zark --time`): `bench/w.zk` (10k lines) frontend 43 ms, native backend 25 ms, link 41 ms; `selfhost/main.zk` frontend 165 ms, native backend 130 ms, link 67 ms. Compare new numbers only against these two rows and with interleaved runs.
- Compiler size: `selfhost/gen*.zk` about 3.4k lines, `src/*.zig` about 4k lines.

## Decisions

- The repository was already under git when the redesign began (the prompt assumed it was not). Phase 0 therefore only adds this file.
- `GUIDE.md` does not exist; the guide lives in `docs-src/pages` (built into `docs/`). "Keep GUIDE.md true" means keeping those pages true.
- Golden token files cover `examples/`, `examples/interop/` and `tests/errors/` only. Files that change often (`selfhost/*`, the std) would make the goldens stale; the compiler building itself already exercises the lexer on them.
- `legacy/zig-stage0/` includes `build.zig` and is archival: it embeds the old `src/std.zk` path and no longer builds.
- The seed is the IR of `selfhost/main.zk` produced by a stage2 that passed the fixed-point check; building it again from the seed gives a byte-identical stage2.
- Language changes follow a two-step workflow once the Zig stage0 is gone: (a) teach the compiler the feature without using it and regenerate the seed; (b) then use it in `selfhost/`.

## Checklist

### Phase 0: safety net
- [x] git repository, `.gitignore`
- [x] `DESIGN.md` committed

### Phase 1: freeze stage0
- [x] `bootstrap/seed.ll.gz` generated from a fixed-point-checked stage
- [x] `bootstrap.sh`: seed -> stage1 -> stage2 -> stage3 -> native chain -> tests, no Zig
- [x] `tools/update-seed.sh`
- [x] `src/*.zig` moved to `legacy/zig-stage0/`, `src/std.zk` moved to `std/std.zk`, `embed` path updated
- [x] golden token files `tests/tokens/*.tok` replace the Zig lexer comparison
- [x] language-change workflow documented in `CLAUDE.md`

### Phase 2: `Fmt`, `print` and friends move to std
- [x] `Fmt` type and lowering of literals with `{...}` holes
- [x] variadic-by-`Fmt` call rule (last parameter of type `Fmt` receives the remaining arguments)
- [x] std: `Writer`, `print`, `println`, `eprint`, `eprintln`, `bprint`, `sprint` in plain Zark
- [x] std: per-type `fmt` for ints, bool, str, pointers, chars; spec parser
- [x] compiler-synthesized `fmt` for structs, unions, enums, arrays, slices, errors (one file)
- [x] floats through libc `snprintf` (TODO libc-free)
- [x] stdout writer keeps ordering with C stdio
- [x] `panic`/`assert` lower to `__panic(file, line, Fmt)`
- [x] delete `gen_fmt.zk` except Fmt lowering, `embed`, `sizeof`, `fmt` synthesis
- [x] `tests/no_magic_names.sh` wired into `bootstrap.sh`
- [x] byte-identical test output on default, `--llvm`, `-O`; fixed points; compile time within +10%

Phase 2 decisions and measurements:
- Per-type formatting is generated as Zark source text (`fn __ff<N>(w, p, spec, depth)`), parsed and added like any declaration, so `?`, `match` and loops come for free. Hole types are named in that text through `rtypes` aliases (`__ft<N>`). Only one file (`gen_fmt.zk`) knows about this. The protocol names the compiler may use are `Fmt`, `Writer`, `__fmt_*`, `__panic`, `__errname`, `__oob`, `__str_eq` and `Option`; `tests/no_magic_names.sh` guards the rest (it covers `gen*`, `parser`, `loader`, `resolve`, `lexer`; `analysis.zk` and `ide.zk` are editor tooling and still mention `List`/`Option` for hover).
- Struct and union display is generated; `fmt` methods written by the user win. Primitive leaves are std functions called by name from the thunks (`__fmt_int` ...), not methods, so no `impl i64` is needed.
- Behaviour changes, all intended: a bad spec is a run-time `<bad format>` (it was a compile error); `{s:.3}` truncates (it printed garbage); `bprint`/`sprint` now format slices, unions and `!T` like `print` does (they used a reduced form); `!void` prints as `void`; a call evaluates its `Fmt` holes before its fixed arguments.
- Name clash fixed: the formatter in `selfhost/fmt.zk` used a struct called `Fmt`; it is now `Formatter`.
- Compile time (min of 15 interleaved runs, old vs new): `bench/w.zk` frontend 76 -> 57 ms, backend 44 -> 44 ms; `selfhost/main.zk` frontend 113 -> 99 ms, backend 97 -> 104 ms (+7%); `examples/hello.zk` frontend 1.7 -> 3.2 ms and backend 0.7 -> 2.5 ms (the std formatting code is now compiled when used; absolute cost about 3 ms).
- Run time: 300k `println("line {i} value {i*3:08x} and {i % 7}")` takes 90 ms before and 450 ms with the default native backend (its code is unoptimised) and 99 ms with `-O`. Output is byte-identical (same md5).

### Phase S: C++-like surface syntax (decided with the owner, not started)

Goal: code that reads like C++ for someone who writes C++ every day, while keeping Zark's semantics. Decisions:

- **Declarations are type-first.** `i64 add(i64 a, i64 b) { ... }`, `i64 x = 5;`, `auto p = Point{ .x = 3, .y = 4 };`. No `fn`, `let`, `var`. A statement starting with `Type name` is a declaration; Zark has no expression statements besides calls and assignments, so `Type* p` is unambiguous with a short lookahead.
- **Mutable by default, `const` for immutable.** Parameters are mutable local copies. `const` keeps today's `let` rules (no change through fields or elements). Closure captures are written `[&k](i64 x) -> i64 { ... }` (by reference, context on the stack, as today).
- **Semicolons are mandatory** in the new syntax. This removes the "operator at the start of a line" trap.
- **Parentheses in `if`/`while`/`for`, braces stay mandatory.** `for (i64 i = 0; i < n; i++)`, range form `for (auto x : xs)` and `for (i64 i : 0..n)`. `++`, `--`, and all compound assignments (`|= &= ^= <<= >>=`) are added.
- **Types:** `T*` pointer, `T[]` slice, `T[N]` array, `!T` error union, `?T` optional, `nullptr`. Only the explicit names `i8..i64`, `u8..u64`, `f32`, `f64`, `bool`, `str`, plus `auto`. No `int`/`long`/`double` aliases.
- **Methods live inside `struct`** (also `union`, `enum`): `i64 len2() const { return x * x + y * y; }`. Fields are visible by bare name and as `this->x` (`.` also works). `const` methods get a read-only receiver; others get `*Self`. `static` marks functions without a receiver. `impl` blocks go away.
- **Generics use `template`:** `template<T: Ord> T max(T a, T b)`, `struct Pair<A, B> { ... }`, `List<i64>`, `max<i64>(1, 2)`. Angle brackets are parsed by speculation (`name <` types `> (`), not by symbol lookup.
- **Scope:** `Color::Red`, `net::connect(...)`; `->` is accepted for member access through pointers (same as `.`).
- **Kept as they are:** `match`, `defer`/`errdefer`, `?`/`catch`/`orelse`, `is`, string interpolation, `import "file" as name;`, `test "name" { }`, `sizeof`/`alignof`, `as` casts, `extern`/`export`.
- **Migration:** the parser accepts both syntaxes and produces the same AST. `zark fmt --to-new` rewrites sources from the AST. Steps: (1) the parser learns the new syntax (two-step seed workflow), (2) the converter rewrites `selfhost/`, `std/`, `examples/`, `tests/` and the guide, (3) the old syntax is removed. Bare member names need a small name-resolution hook in `gen` first and move into `sema` in Phase 3.
- Steps S1 parser, S2 converter, S3 migrate everything, S4 remove the old syntax, S5 guide and editor grammar. Each step green: tests, both fixed points, `tests/no_magic_names.sh`.

### Phase 3: semantic layer
- [x] `sema*.zk`: types and layouts (`sema_types.zk`, moved out of `gen.zk` unchanged, IR byte-identical)
- [ ] expression typing, calls and generics, statements: still interleaved with IR emission in `gen*.zk`; splitting them is the next big step and needs a typed AST
- [x] no duplicated logic found to delete (the old parser paths were removed in S4)
- [x] several errors per run (up to 10); decided: the column stays in the caret line, the header keeps `file:line:` (the LSP and the guide builder parse it)
- [x] `const` methods cannot assign fields (and call non-const methods through `this`; calls on const variables are allowed)
- [x] constraints `T: Ord` checked at the declaration (`sema_check.zk`: operators on values of type `T` against the declared constraint; unconstrained parameters are still checked at the instantiation)
- [ ] interfaces defined in std
- [ ] all tests on three backends, fixed points, compile time within +10%

S1 as built, and where it differs from the plan:
- Semicolons are accepted but not required: the lexer still inserts them at line ends, so the "operator at the start of a line" trap remains. Enforcing them needs a per-file mode and is left for S4.
- `for (T i = a; i < b; i++)` (also `<=`, `++i`, `i += 1`) is lowered to the range loop; other C-style loops are rejected with a message that points to `while`. Index form `for (i, x : xs)` is not supported yet.
- `const` on a method and parameters are parsed; methods get a `this` pointer, `const` is not enforced (Phase 3). Parameters are mutable copies in the new syntax only.
- `T[N]` is an array for builtin type names and for any type when `N` is an integer literal; `Name[T]` stays the old generic form. Casts take pointer types in prefix form (`p as *u8`).
- A designated literal (`Point{ .x = 1 }`) zero-fills the rest, as in C++.
- `zark fmt` keeps new-syntax files stable (spacing around `<`, `>`, `::`, `->`, `*` follows the source); a real printer is part of S2.

Migration notes (S2/S3a): the compiler (11.8k lines), std, examples and tests were converted by the script and re-formatted with `zark fmt`; `bootstrap.sh`, all three backends, both fixed points and the no-magic check pass. Parser additions made on the way: methods and `template` members inside `struct`/`union`/`enum`, out-of-class definitions (`R Type::name(...)`, `template<T> R Type<T>::name(...)`), `for (auto [i, x] : seq)`, function-pointer declarations as statements, generic types in casts, explicit template arguments on method calls (`a.create<T>()`).

### Phase S checklist
- [x] S1 parser accepts the new syntax (`selfhost/parser_new.zk`, example `examples/cpp_style.zk`, guide page `cpp-style.md`)
- [x] S2 converter: `python3 tools/convert-syntax.py FILE...` rewrites old-syntax files in place (token based, keeps comments; run `zark fmt` after it). It is a script, not a `zark fmt` flag, because it is only needed once
- [x] S3a migrate selfhost, std, examples, tests (done; every method of a struct that lives in another file is an out-of-class definition, `void Gen::gen_expr(...)`)
- [x] S3b migrate the guide (code blocks and the prose that explains `fn`/`let`/`var`/`impl`), README, SPEC examples
- [x] S4 remove the old syntax (`;` is mandatory except before `}`)
- [x] S5 guide, editor grammar and snippets

### Phase D: low-level programming (drivers, kernels)
- [x] `volatile` (pointees, fields, variables), `packed struct`
- [x] `asm<R>(template, constraints, args...)` with native encodings for the prelude templates
- [x] prelude: `Cpu`, `Port`, `Bits`, `Atomic`, `Spinlock`
- [x] `--freestanding`, linker script and `.S` passthrough, `export` replaces an `extern` of the same name
- [x] `examples/baremetal`: boots in QEMU, serial through `Fmt`, IDT and an exception handled in Zark; tested on both backends
- [x] `align(N)` on global variables, 8/16-bit atomics
- [x] `align(N)` on struct types and locals
- [ ] an `interrupt` function attribute, bitfields, aarch64/riscv targets

### Phase O: types with behavior
- [x] default field values, constructors, interfaces with dynamic dispatch, operator methods
- [x] decided against: implementation inheritance, destructors called implicitly, `[]`/`()`/`<<` overloading
- [x] `--fast` (nsw), `inbounds` indexing, `List` growth by `realloc`, faster `sort`; `tools/fuzz.py` compares the three backends on random programs

### Phase 4 (only when asked): MIR and backend work
