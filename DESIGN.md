# Vibe: "no magic in the compiler" redesign

This file is the resume point. Work top to bottom; continue from the first unchecked item.

## Goal

The compiler stops knowing standard-library names and is split into layers: `parse -> sema (typed AST) -> lowering -> backends`. Everything else (`print`, formatting, `List`, `Map`, allocators, `sort`) is ordinary Vibe code in the std. Vibe stays clearer than Zig (no `anytype`, no implicit comptime) and fast: no phase of compile time may regress by more than 10%.

## Baseline (recorded before Phase 1)

- Tests: 21/21 (`tests/run.sh`), fixed points stage2 == stage3 and native2 == native3.
- Compile time: see `bench/compile_speed.sh` (to be recorded here).
- Compiler size: `selfhost/gen*.vibe` about 3.4k lines, `src/*.zig` about 4k lines.

## Decisions

- The repository was already under git when the redesign began (the prompt assumed it was not). Phase 0 therefore only adds this file.
- `GUIDE.md` does not exist; the guide lives in `docs-src/pages` (built into `docs/`). "Keep GUIDE.md true" means keeping those pages true.
- Language changes follow a two-step workflow once the Zig stage0 is gone: (a) teach the compiler the feature without using it and regenerate the seed; (b) then use it in `selfhost/`.

## Checklist

### Phase 0: safety net
- [x] git repository, `.gitignore`
- [x] `DESIGN.md` committed

### Phase 1: freeze stage0
- [ ] `bootstrap/seed.ll` (gzipped) generated from a fixed-point-checked stage
- [ ] `bootstrap.sh`: seed -> stage1 -> stage2 -> stage3 -> native chain -> tests, no Zig
- [ ] `tools/update-seed.sh`
- [ ] `src/*.zig` moved to `legacy/zig-stage0/`, `src/std.vibe` moved to `std/std.vibe`, `embed` path updated
- [ ] golden token files `tests/tokens/*.tok` replace the Zig lexer comparison
- [ ] language-change workflow documented in `CLAUDE.md`

### Phase 2: `Fmt`, `print` and friends move to std
- [ ] `Fmt` type and lowering of literals with `{...}` holes
- [ ] variadic-by-`Fmt` call rule (last parameter of type `Fmt` receives the remaining arguments)
- [ ] std: `Writer`, `print`, `println`, `eprint`, `eprintln`, `bprint`, `sprint` in plain Vibe
- [ ] std: per-type `fmt` for ints, bool, str, pointers, chars; spec parser
- [ ] compiler-synthesized `fmt` for structs, unions, enums, arrays, slices, errors (one file)
- [ ] floats through libc `snprintf` (TODO libc-free)
- [ ] stdout writer keeps ordering with C stdio
- [ ] `panic`/`assert` lower to `__panic(file, line, Fmt)`
- [ ] delete `gen_fmt.vibe` except Fmt lowering, `embed`, `sizeof`, `fmt` synthesis
- [ ] `tests/no_magic_names.sh` wired into `bootstrap.sh`
- [ ] byte-identical test output on default, `--llvm`, `-O`; fixed points; compile time within +10%

### Phase 3: semantic layer
- [ ] `sema*.vibe`: types and layouts
- [ ] expression typing
- [ ] calls and generics
- [ ] statements
- [ ] delete duplicated logic in `gen*.vibe`
- [ ] several errors per run (up to 10) with `file:line:col`
- [ ] constraints `T: Ord` checked at the declaration, interfaces defined in std
- [ ] all tests on three backends, fixed points, compile time within +10%

### Phase 4 (only when asked): MIR and backend work
