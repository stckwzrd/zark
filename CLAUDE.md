# Vibe — context for Claude Code

Vibe is a Zig-like systems language. The compiler is self-hosted, and the default backend is our own x86-64 code generator. LLVM is used only for `--release`. The project owner writes in Russian.

## Layout
- `selfhost/*.vibe`: **the real compiler**, about 6.2k lines of Vibe.
  - `lexer` → `ast` (fat nodes with a kind tag) → `parser`.
  - `sema_types.vibe`: type layouts, names, resolution, constraints (first piece of the semantic layer).
  - `gen*.vibe`: generics, statements, expressions, calls, formatting. Emits LLVM IR **as text**.
  - `native.vibe`: parses that IR and lowers it to x86-64 (System V ABI, every SSA value in a stack slot).
  - `x64.vibe`: encoder + ELF `.o` writer.
  - `main.vibe`: the driver.
- `std/std.vibe`: the prelude, embedded into the compiler with `embed`.
- `std/<name>.vibe`: standard modules (fs, path, time, os, args, json, net, http, thread), also embedded; `import "std/fs" as fs;` loads `<std>/fs.vibe` (`selfhost/loader.vibe`). A new module needs a line in `std_source` there, and the compiler must be rebuilt to pick up module changes.
- `tests/std/*.vibe`: `test` blocks for the standard library, run by `tests/run.sh`.
- `bootstrap/seed.ll.gz`: the bootstrap seed, the LLVM IR of the compiler itself. `./bootstrap.sh` builds stage1 from it with clang; no other compiler is needed.
- `legacy/zig-stage0/`: the old Zig compiler, kept for history only. It is not built and not maintained.
- `tools/update-seed.sh`: regenerates the seed from a stage that passed the fixed-point check.
- `examples/baremetal/`: an x86-64 kernel in Vibe that boots in QEMU (`tests/baremetal.sh`); `tests/asm_encoding.sh` checks the native encodings of the privileged instructions against LLVM.
- `examples/`, `tests/run.sh` + `tests/expected/`, `tests/errors/` (programs that must fail to compile), `tests/tokens/` (golden token dumps of the examples).
- `bench/compile_speed.sh`: compile time against gcc and clang.
- Docs: `SPEC.md` (the language contract), `BOOTSTRAP.md`, `ROADMAP.md` (next steps).

## Commands
- `./bootstrap.sh` does everything:
  1. seed → stage1 → stage2 → stage3 through LLVM, checks stage2 == stage3.
  2. Builds the native-only chain native1 → native2 → native3, checks native2 == native3.
  3. Runs the tests.
  4. Writes the result to `build/vibe`.
- `VIBE=build/vibe tests/run.sh`: run the tests. `FLAGS=--llvm` or `FLAGS=-O` tests the other backends. All tests must pass.
- `build/vibe run|build|ir|tokens file.vibe [x.c y.cpp] [-o out] [-O|--release|--llvm|--native] [--time]`
- clang 18 is required (it builds the seed, links programs and runs `--release`). Zig is not needed.

## Invariants (do not break)
1. The fixed points must hold: stage2 == stage3, native2 == native3.
2. **New syntax or builtins reach `selfhost/` in two steps.** (a) Teach the compiler the feature without using it in `selfhost/`, run `./bootstrap.sh`, then `tools/update-seed.sh` and commit the new seed. (b) Only then use the feature in `selfhost/`. Using it earlier makes the old seed unable to build stage1.
3. The language rule: **no hidden allocations**. Memory goes only through an explicit `Allocator`. String interpolation is allowed only as an argument of a function whose last parameter is a `Fmt` (the std print family, your own).
5. The compiler must not know std names (`tests/no_magic_names.sh`, run by `bootstrap.sh`). The protocol names it may use are listed in `SPEC.md` section 6.
4. The lexer output must match `tests/tokens/*.tok`. After an intended lexer change, regenerate them with `build/vibe tokens FILE > tests/tokens/NAME.tok` (NAME is the path with `/` replaced by `_`) and review the diff.

## Syntax
The language is written C++-style: type-first declarations, `auto`/`const`, `template<T>`, methods inside `struct` or out of class as `R Type::name()`, `[&k](T x) -> R {}`, `for (T x : seq)`, `T{ .f = v }` (rest zeroed), mandatory `;` (not needed before `}`). The old `fn`/`let`/`var`/`impl` spelling is gone. `tools/convert-syntax.py FILE` converts old code.

## Gotchas when writing Vibe (the compiler is written in it too)
- `{` inside a string starts interpolation. For a literal brace write `{{` / `}}`. IR text like `"{{ ptr, i64 }}"` is the usual case.
- A struct literal sets the listed fields with `.f = v` and zeroes the rest. `T{` is only recognized when the type name starts with an uppercase letter.
- `create<T>()` returns zeroed memory. A zero `List`/`Map` has no allocator, so call `.init(a)` before `push`.
- `Map.get` returns a copy (`!V`). To modify a value in place, use `&m.entries[m.__find(k)]`.
- `as` binds weaker than prefix operators: `&x as *T` means `(&x) as *T`. Write `(e catch 0) as i64` with the parentheses.
- Enum and union literals `.X` need a type known from context. `x is .X` tests a variant.
- `const` forbids changes through fields as well. Variables are mutable by default.

## Status and next steps (details in ROADMAP.md)
- Compile time for 10k lines: about 95 ms (clang -O0 about 220 ms, gcc -O0 about 670 ms).
- Weak spot: code from the native backend runs about 3x slower than gcc -O0.
- Planned order:
  1. Register allocation (linear scan) + SSA without allocas + peephole.
  2. In-memory IR instead of text (removes print + parse).
  3. Own linker + a libc-free runtime on Linux syscalls.
  4. SIMD types, closures with an explicit context, `T: Ord` constraints, `match` as an expression, `comptime`.
  5. `vibe fmt`, `vibe test`, DWARF debug info.
