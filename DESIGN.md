# Vibe: "no magic in the compiler" redesign

This file is the resume point. Work top to bottom; continue from the first unchecked item.

## Goal

The compiler stops knowing standard-library names and is split into layers: `parse -> sema (typed AST) -> lowering -> backends`. Everything else (`print`, formatting, `List`, `Map`, allocators, `sort`) is ordinary Vibe code in the std. Vibe stays clearer than Zig (no `anytype`, no implicit comptime) and fast: no phase of compile time may regress by more than 10%.

## Baseline (recorded before Phase 1)

- Tests: 21/21 (`tests/run.sh`), fixed points stage2 == stage3 and native2 == native3.
- Compile time (min of 7-12 runs on a noisy machine, `build/vibe --time`): `bench/w.vibe` (10k lines) frontend 43 ms, native backend 25 ms, link 41 ms; `selfhost/main.vibe` frontend 165 ms, native backend 130 ms, link 67 ms. Compare new numbers only against these two rows and with interleaved runs.
- Compiler size: `selfhost/gen*.vibe` about 3.4k lines, `src/*.zig` about 4k lines.

## Decisions

- The repository was already under git when the redesign began (the prompt assumed it was not). Phase 0 therefore only adds this file.
- `GUIDE.md` does not exist; the guide lives in `docs-src/pages` (built into `docs/`). "Keep GUIDE.md true" means keeping those pages true.
- Golden token files cover `examples/`, `examples/interop/` and `tests/errors/` only. Files that change often (`selfhost/*`, the std) would make the goldens stale; the compiler building itself already exercises the lexer on them.
- `legacy/zig-stage0/` includes `build.zig` and is archival: it embeds the old `src/std.vibe` path and no longer builds.
- The seed is the IR of `selfhost/main.vibe` produced by a stage2 that passed the fixed-point check; building it again from the seed gives a byte-identical stage2.
- Language changes follow a two-step workflow once the Zig stage0 is gone: (a) teach the compiler the feature without using it and regenerate the seed; (b) then use it in `selfhost/`.

## Checklist

### Phase 0: safety net
- [x] git repository, `.gitignore`
- [x] `DESIGN.md` committed

### Phase 1: freeze stage0
- [x] `bootstrap/seed.ll.gz` generated from a fixed-point-checked stage
- [x] `bootstrap.sh`: seed -> stage1 -> stage2 -> stage3 -> native chain -> tests, no Zig
- [x] `tools/update-seed.sh`
- [x] `src/*.zig` moved to `legacy/zig-stage0/`, `src/std.vibe` moved to `std/std.vibe`, `embed` path updated
- [x] golden token files `tests/tokens/*.tok` replace the Zig lexer comparison
- [x] language-change workflow documented in `CLAUDE.md`

### Phase 2: `Fmt`, `print` and friends move to std
- [x] `Fmt` type and lowering of literals with `{...}` holes
- [x] variadic-by-`Fmt` call rule (last parameter of type `Fmt` receives the remaining arguments)
- [x] std: `Writer`, `print`, `println`, `eprint`, `eprintln`, `bprint`, `sprint` in plain Vibe
- [x] std: per-type `fmt` for ints, bool, str, pointers, chars; spec parser
- [x] compiler-synthesized `fmt` for structs, unions, enums, arrays, slices, errors (one file)
- [x] floats through libc `snprintf` (TODO libc-free)
- [x] stdout writer keeps ordering with C stdio
- [x] `panic`/`assert` lower to `__panic(file, line, Fmt)`
- [x] delete `gen_fmt.vibe` except Fmt lowering, `embed`, `sizeof`, `fmt` synthesis
- [x] `tests/no_magic_names.sh` wired into `bootstrap.sh`
- [x] byte-identical test output on default, `--llvm`, `-O`; fixed points; compile time within +10%

Phase 2 decisions and measurements:
- Per-type formatting is generated as Vibe source text (`fn __ff<N>(w, p, spec, depth)`), parsed and added like any declaration, so `?`, `match` and loops come for free. Hole types are named in that text through `rtypes` aliases (`__ft<N>`). Only one file (`gen_fmt.vibe`) knows about this. The protocol names the compiler may use are `Fmt`, `Writer`, `__fmt_*`, `__panic`, `__errname`, `__oob`, `__str_eq` and `Option`; `tests/no_magic_names.sh` guards the rest (it covers `gen*`, `parser`, `loader`, `resolve`, `lexer`; `analysis.vibe` and `ide.vibe` are editor tooling and still mention `List`/`Option` for hover).
- Struct and union display is generated; `fmt` methods written by the user win. Primitive leaves are std functions called by name from the thunks (`__fmt_int` ...), not methods, so no `impl i64` is needed.
- Behaviour changes, all intended: a bad spec is a run-time `<bad format>` (it was a compile error); `{s:.3}` truncates (it printed garbage); `bprint`/`sprint` now format slices, unions and `!T` like `print` does (they used a reduced form); `!void` prints as `void`; a call evaluates its `Fmt` holes before its fixed arguments.
- Name clash fixed: the formatter in `selfhost/fmt.vibe` used a struct called `Fmt`; it is now `Formatter`.
- Compile time (min of 15 interleaved runs, old vs new): `bench/w.vibe` frontend 76 -> 57 ms, backend 44 -> 44 ms; `selfhost/main.vibe` frontend 113 -> 99 ms, backend 97 -> 104 ms (+7%); `examples/hello.vibe` frontend 1.7 -> 3.2 ms and backend 0.7 -> 2.5 ms (the std formatting code is now compiled when used; absolute cost about 3 ms).
- Run time: 300k `println("line {i} value {i*3:08x} and {i % 7}")` takes 90 ms before and 450 ms with the default native backend (its code is unoptimised) and 99 ms with `-O`. Output is byte-identical (same md5).

### Phase S: C++-like surface syntax (decided with the owner, not started)

Goal: code that reads like C++ for someone who writes C++ every day, while keeping Vibe's semantics. Decisions:

- **Declarations are type-first.** `i64 add(i64 a, i64 b) { ... }`, `i64 x = 5;`, `auto p = Point{ .x = 3, .y = 4 };`. No `fn`, `let`, `var`. A statement starting with `Type name` is a declaration; Vibe has no expression statements besides calls and assignments, so `Type* p` is unambiguous with a short lookahead.
- **Mutable by default, `const` for immutable.** Parameters are mutable local copies. `const` keeps today's `let` rules (no change through fields or elements). Closure captures are written `[&k](i64 x) -> i64 { ... }` (by reference, context on the stack, as today).
- **Semicolons are mandatory** in the new syntax. This removes the "operator at the start of a line" trap.
- **Parentheses in `if`/`while`/`for`, braces stay mandatory.** `for (i64 i = 0; i < n; i++)`, range form `for (auto x : xs)` and `for (i64 i : 0..n)`. `++`, `--`, and all compound assignments (`|= &= ^= <<= >>=`) are added.
- **Types:** `T*` pointer, `T[]` slice, `T[N]` array, `!T` error union, `?T` optional, `nullptr`. Only the explicit names `i8..i64`, `u8..u64`, `f32`, `f64`, `bool`, `str`, plus `auto`. No `int`/`long`/`double` aliases.
- **Methods live inside `struct`** (also `union`, `enum`): `i64 len2() const { return x * x + y * y; }`. Fields are visible by bare name and as `this->x` (`.` also works). `const` methods get a read-only receiver; others get `*Self`. `static` marks functions without a receiver. `impl` blocks go away.
- **Generics use `template`:** `template<T: Ord> T max(T a, T b)`, `struct Pair<A, B> { ... }`, `List<i64>`, `max<i64>(1, 2)`. Angle brackets are parsed by speculation (`name <` types `> (`), not by symbol lookup.
- **Scope:** `Color::Red`, `net::connect(...)`; `->` is accepted for member access through pointers (same as `.`).
- **Kept as they are:** `match`, `defer`/`errdefer`, `?`/`catch`/`orelse`, `is`, string interpolation, `import "file" as name;`, `test "name" { }`, `sizeof`/`alignof`, `as` casts, `extern`/`export`.
- **Migration:** the parser accepts both syntaxes and produces the same AST. `vibe fmt --to-new` rewrites sources from the AST. Steps: (1) the parser learns the new syntax (two-step seed workflow), (2) the converter rewrites `selfhost/`, `std/`, `examples/`, `tests/` and the guide, (3) the old syntax is removed. Bare member names need a small name-resolution hook in `gen` first and move into `sema` in Phase 3.
- Steps S1 parser, S2 converter, S3 migrate everything, S4 remove the old syntax, S5 guide and editor grammar. Each step green: tests, both fixed points, `tests/no_magic_names.sh`.

### Phase 3: semantic layer
- [ ] `sema*.vibe`: types and layouts
- [ ] expression typing
- [ ] calls and generics
- [ ] statements
- [ ] delete duplicated logic in `gen*.vibe`
- [ ] several errors per run (up to 10) with `file:line:col`
- [ ] constraints `T: Ord` checked at the declaration, interfaces defined in std
- [ ] all tests on three backends, fixed points, compile time within +10%

### Phase S checklist
- [ ] S1 parser accepts the new syntax
- [ ] S2 `vibe fmt --to-new`
- [ ] S3 migrate selfhost, std, examples, tests, guide
- [ ] S4 remove the old syntax
- [ ] S5 guide, editor grammar and snippets

### Phase 4 (only when asked): MIR and backend work
