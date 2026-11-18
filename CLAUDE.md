# Vibe — context for Claude Code

Vibe is a Zig-like systems language. The compiler is self-hosted, and the default backend is our own x86-64 code generator. LLVM is used only for `--release`. The project owner writes in Russian.

## Layout
- `selfhost/*.vibe`: **the real compiler**, about 6.2k lines of Vibe.
  - `lexer` → `ast` (fat nodes with a kind tag) → `parser`.
  - `gen*.vibe`: types, generics, statements, expressions, calls, formatting. Emits LLVM IR **as text**.
  - `native.vibe`: parses that IR and lowers it to x86-64 (System V ABI, every SSA value in a stack slot).
  - `x64.vibe`: encoder + ELF `.o` writer.
  - `main.vibe`: the driver.
- `src/*.zig`: stage0 compiler (Zig 0.13) used only to start the bootstrap, plus the reference lexer. `src/std.vibe` is the prelude, embedded into both compilers.
- `examples/`, `tests/run.sh` + `tests/expected/`, `tests/errors/` (programs that must fail to compile).
- `bench/compile_speed.sh`: compile time against gcc and clang.
- Docs: `SPEC.md` (the language contract), `BOOTSTRAP.md`, `ROADMAP.md` (next steps).

## Commands
- `./bootstrap.sh` does everything:
  1. Zig stage0 → stage1 → stage2 → stage3 through LLVM, checks stage2 == stage3.
  2. Builds the native-only chain native1 → native2 → native3, checks native2 == native3.
  3. Runs the tests.
  4. Writes the result to `build/vibe`.
- `VIBE=build/vibe tests/run.sh`: run the tests. `FLAGS=--llvm` or `FLAGS=-O` tests the other backends. 21 tests, all must pass.
- `build/vibe run|build|ir|tokens file.vibe [x.c y.cpp] [-o out] [-O|--release|--llvm|--native] [--time]`
- Zig if it is missing: `pip install ziglang==0.13.0 --break-system-packages`, then call it as `python3 -m ziglang`. clang 18 is also required (for linking and `--release`).

## Invariants (do not break)
1. The fixed points must hold: stage2 == stage3, native2 == native3.
2. **Any new syntax or builtin that `selfhost/` itself uses must also be added to `src/*.zig`**, otherwise stage0 cannot build stage1. The other way out is to bootstrap from the previous `build/vibe` and freeze stage0.
3. The language rule: **no hidden allocations**. Memory goes only through an explicit `Allocator`. String interpolation is allowed only in `print/println/eprint/eprintln/panic/bprint/sprint`.
4. The lexer in `selfhost/lexer.vibe` must match the Zig lexer token for token (a test checks this). New keywords go into both.

## Gotchas when writing Vibe (the compiler is written in it too)
- `{` inside a string starts interpolation. For a literal brace write `{{` / `}}`. IR text like `"{{ ptr, i64 }}"` is the usual case.
- A struct literal must list all fields, or end with `..` to zero the rest. `T{` is only recognized when the type name starts with an uppercase letter.
- `create[T]()` returns zeroed memory. A zero `List`/`Map` has no allocator, so call `.init(a)` before `push`.
- `Map.get` returns a copy (`!V`). To modify a value in place, use `&m.entries[m.__find(k)]`.
- `as` binds weaker than prefix operators: `&x as *T` means `(&x) as *T`. Write `(e catch 0) as i64` with the parentheses.
- Enum and union literals `.X` need a type known from context. `x is .X` tests a variant.
- `let` forbids changes through fields as well. Use `var` for mutable values.

## Status and next steps (details in ROADMAP.md)
- Compile time for 10k lines: about 95 ms (clang -O0 about 220 ms, gcc -O0 about 670 ms).
- Weak spot: code from the native backend runs about 3x slower than gcc -O0.
- Planned order:
  1. Register allocation (linear scan) + SSA without allocas + peephole.
  2. In-memory IR instead of text (removes print + parse).
  3. Own linker + a libc-free runtime on Linux syscalls.
  4. SIMD types, closures with an explicit context, `T: Ord` constraints, `match` as an expression, `comptime`.
  5. `vibe fmt`, `vibe test`, DWARF debug info.
