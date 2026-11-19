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
