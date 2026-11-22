# C/C++ build integration and `import "header.h"` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zark builds C/C++ sources with flags, `pkg-config` and a content-addressed object cache, and `import "x.h"` turns a C header into Zark declarations.

**Architecture:** A new `selfhost/cbuild.zk` owns flag classification, object compilation, the cache and `pkg-config`; `main.zk` and `project.zk` call into it. A new `selfhost/cbind.zk` runs `clang -E -dD` on a stub that includes the header, parses the preprocessed declarations with a small C declaration parser, and emits Zark source; `loader.zk` routes `import "*.h"` to it and caches the result. No language or syntax change, so no seed round trip is needed (update the seed once at the end for hygiene).

**Tech Stack:** Zark (the compiler is written in it), clang as preprocessor/compiler, bash tests in the style of `tests/project.sh`.

**Spec:** `docs/superpowers/specs/2026-11-22-ffi-build-and-cbind-design.md`. Read it first and read `CLAUDE.md` (invariants, Zark gotchas: `{` in strings, `as T*` before `;` or `)` parses as multiplication, `type` is a keyword, a struct literal is `T{ .f = v }`).

## Global Constraints

- No comments in code, configs, scripts or workflows (the owner's rule). Comments others wrote stay.
- No language, syntax or `vrt_*` changes. The compiler source must build with the current seed.
- The fixed points must hold: stage2 == stage3 (IR everywhere, binary on Linux), native2 == native3 (Linux x86-64). `./bootstrap.sh` must finish green after every task, and `ZARK=build/zark tests/run.sh` must pass, also with `FLAGS=--llvm`.
- The compiler must not know std names (`tests/no_magic_names.sh`).
- Only `clang`/`clang++` and `pkg-config` are external tools. `pkg-config` is optional (tests skip when absent).
- A binding the tool cannot express exactly is skipped with a warning on stderr, never emitted wrong.
- Platforms: Linux x86_64/arm64, macOS arm64/Intel (Apple clang), WSL. Struct-by-value tests stay x86-64 only. LP64 only (`long` is `i64`).
- Commit messages: one short imperative line, no mention of AI, no `Co-Authored-By`. Work on branch `ffi-build-cbind`; push after every green task.
- Cache layout under `.zark-cache/`: `obj/<base>-<hash>.o` (+ `.d`, `.stamp`) and `cbind/<hash>.zk` (+ `<hash>.c` when inline wrappers exist).

## Review Focus

1. Editing a header that a source or a bound header includes must rebuild the object and regenerate the bindings (Task 3, Task 9 tests).
2. Paths with spaces in include dirs, sources and header names must work end to end (Task 1, Task 9 tests).
3. The same header imported from two Zark files, or twice with different aliases, must not duplicate or clash (Task 9 test).
4. Nested anonymous structs/unions, arrays of structs and self-referential pointers (`struct node { struct node* next; }`) must map exactly (Task 5, Task 7 tests).
5. Macro and enum values with negative numbers, `u`/`UL` suffixes, char literals, shifts and references to earlier names must evaluate or be skipped, never emitted wrong (Task 6 test).
6. Two `zark` processes sharing one `.zark-cache` must not corrupt it (temp file plus `mv` for every cache write; Task 3 test).

## File Structure

- Create `selfhost/cbuild.zk`: flag classification, `pkg-config`, object compile, cache, parallelism.
- Create `selfhost/cbind.zk`: preprocess, C tokenizer, declaration parser, type mapping, emitter, cache entry point.
- Modify `selfhost/main.zk`: use `cbuild`; `zark cbind` command; sources-only link path; remove the inline compile loop.
- Modify `selfhost/project.zk`: new `[build]` fields, propagation from dependencies, `project_args` emits flags.
- Modify `selfhost/loader.zk`: `.h` imports.
- Create `tests/cbuild.sh`, `tests/cbind.sh`, `tests/cbind/*`; hook both into `tests/run.sh` next to `project.sh`.
- Modify `examples/imgui/*`, `SPEC.md` section 8, `README.md`, the FFI guide page in `docs-src/pages` if one exists.

---

### Task 1: Flag classification and flags on the command line

**Files:**
- Create: `selfhost/cbuild.zk`, `tests/cbuild.sh`
- Modify: `selfhost/main.zk` (the loop that compiles `extras`, about lines 430-451), `tests/run.sh`

**Interfaces:**
- Produces in `cbuild.zk`:
  - `bool is_compile_flag(str x)`: true for `-I*`, `-isystem`, `-D*`, `-U*`, `-std=*`, `-include`, `-f*`, `-W*` except `-Wl,*`, and `-pthread`. `-I dir` with the value as the next argument is not supported; document nothing, just reject it as a source.
  - `struct CSplit { List<str> flags; List<str> sources; List<str> link; }`
  - `!CSplit split_extras(Allocator a, List<str> extras)`: `link` gets `-l*`, `-L*`, `-Wl,*`, `-T*`, `-nostdlib`, `-static`, and anything ending `.o .a .so`; `flags` gets compile flags; everything else is a source.
  - `!List<str> compile_sources(Allocator a, str cache, CSplit* s, str olevel, bool* needs_cxx)`: compiles each source with `clang`/`clang++` (`.cpp .cc .cxx` is C++) and the flags, returns the object paths, sets `*needs_cxx`.
- Consumes: `run(Allocator, str[]) !i32` from the prelude.

- [ ] **Step 1: Write `tests/cbuild.sh`** (bash, `fail()` helper like `tests/project.sh`, temp dir with `trap`) with test `flags_cli`: a C file `a b/ans.c` (directory name with a space) that does `#include "cfg.h"` and defines `long answer(void) { return ANSWER; }`, header `a b/inc/cfg.h` with `#define BASE 40`, and `main.zk` calling `extern i64 answer();` and printing it. Run `$ZARK run main.zk "a b/ans.c" "-Ia b/inc" -DANSWER=42` and assert the output is `42`; run with `-DANSWER=BASE+2` and assert `42`.
- [ ] **Step 2: Run it** (`ZARK=build/zark tests/cbuild.sh`) and see it fail (today `-I...` is passed to the linker as a source and fails).
- [ ] **Step 3: Implement `cbuild.zk`** as specified in Interfaces; replace the loop in `main.zk` with `split_extras` + `compile_sources`; link arguments come from `CSplit.link`. Keep `.S`/`.c`/`.o` freestanding behaviour unchanged. Compile flags also go into `g.ct_extras` the same way extras do today (check how `comptime` uses it).
- [ ] **Step 4: Run `tests/cbuild.sh`** and see `flags_cli` pass; run `./bootstrap.sh` and see it finish green.
- [ ] **Step 5: Hook `tests/cbuild.sh` into `tests/run.sh`** right after the `project.sh` block (same `pass/fail` pattern). Commit: `add C/C++ compile flags`.

### Task 2: Manifest fields, pkg-config, dependency propagation

**Files:**
- Modify: `selfhost/project.zk` (`Manifest`, `load_project`, `project_args`, the commented template in `scaffold_project` stays as is), `tests/cbuild.sh`

**Interfaces:**
- Consumes: `is_compile_flag`, `CSplit` from Task 1.
- `[build]` keys (all optional): `include`, `defines`, `cflags`, `lib-dirs` are string lists; `std` is a string; `pkg-config` is a string list. Paths in `include` and `lib-dirs` are relative to the manifest directory and become absolute.
- Produces: `Manifest` gains `List<str> cflags` (already-formed compile flags: `-I<abs>`, `-D<d>`, `-std=<s>`, then `cflags` entries) and `List<str> pkgs`. `project_args` emits `cflags`, then for each package the result of `pkg-config --cflags --libs <pkg>` classified with `is_compile_flag` (compile) versus link flags, then `-L<abs>` for `lib-dirs`. Dependencies add their `cflags`, `pkgs`, `sources`, `libs` to the parent (like `sources` and `libs` today).
- Errors (exit 1, message on stderr): `pkg-config` not found: `error: pkg-config is not installed (needed for 'sdl2')`; unknown package: include the package name.

- [ ] **Step 1: Add tests** `manifest_fields` (project with `include`, `defines`, `std = "c++17"`, a `.cpp` source using `std::string_view`, `libs = ["stdc++"]`, expected output) and `dependency_flags` (a path dependency with its own `defines` and a source; the app sees the symbol), `pkg_config_missing_package` (needs real pkg-config: skip with a message when `command -v pkg-config` fails; expect the error text with the package name), `pkg_config_ok` (skip unless `pkg-config --exists zlib`; links `-lz` and calls `zlibVersion()` through `extern u8* zlibVersion();`).
- [ ] **Step 2: Run, see them fail.**
- [ ] **Step 3: Implement** the parsing in `load_project` and the emission in `project_args` per Interfaces. Run `pkg-config` once per package per invocation through `std/os` `exec`.
- [ ] **Step 4: Run `tests/cbuild.sh` and `tests/project.sh`**; both pass. Commit: `add build include, defines, std and pkg-config`.

### Task 3: Object cache and parallel compile

**Files:**
- Modify: `selfhost/cbuild.zk` (`compile_sources` internals), `tests/cbuild.sh`

**Interfaces:**
- `compile_sources` keeps its signature. Object path `.zark-cache/obj/<base>-<hash16>.o` where `<hash16>` is a 64-bit FNV-1a (hex, 16 chars) over: compiler name, `olevel`, all flags in order, the source path and its text. Each compile writes `<obj>.tmp.<pid>` with `-MD -MF <obj>.d.tmp.<pid>`, then `mv`s object and `.d`, then writes `<obj>.stamp` (temp plus `mv`) holding the hash of the contents of all files listed in the `.d` file. A hit requires the object, the `.d` and the stamp to exist and the recomputed stamp to match, so a header edit forces a rebuild. Two sources with the same base name get different objects (the hash includes the path).
- Compile jobs run in parallel with `parallel_for` from `std/thread` over the sources that missed, `min(ZARK_JOBS or 8, misses)` threads; a job's stdout/stderr are captured with `exec` and printed in source order after all jobs finish; the first nonzero exit code is returned as the error. Object order in the result equals source order.
- Consumes: `fnv`-style helper local to `cbuild.zk` (`u64 fnv64(u64 h, str s)`), `fs`, `path` modules.
- Also fixes two Task 1 review findings in `selfhost/cbuild.zk`: (a) `split_extras` must test `is_compile_flag` before the `.o/.a/.so` suffix rule, so `-DLIB=libfoo.a` stays a compile flag; (b) `-std=` flags apply per language: `-std=c++*`/`-std=gnu++*` only to C++ sources, any other `-std=` only to C sources, all other compile flags to both. Test: `mixed_c_cpp_std` (one `.c` and one `.cpp` with `-std=c++17` and `-std=c11`, both compile and link).

- [ ] **Step 1: Tests** in `tests/cbuild.sh`: `cache_hit` (build twice with `--time`-free check: second run must not invoke clang, assert via a `PATH` shim `clang` script that appends to a log file and execs the real clang, count lines unchanged on the second run), `cache_header_edit` (edit the included header between runs, assert the new value appears), `same_base_name` (`a/util.c` and `b/util.c` with different functions, both linked), `parallel_determinism` (ten sources, run three times with `ZARK_JOBS=1` and `ZARK_JOBS=8`, program output identical and objects named identically), `concurrent_runs` (two `zark build` in the background into different `-o` with the same cache, both succeed and run).
- [ ] **Step 2: Run, see `cache_*` and `concurrent_runs` fail** (no cache today; the collision test fails too).
- [ ] **Step 3: Implement** per Interfaces.
- [ ] **Step 4: Run `tests/cbuild.sh`**, then `./bootstrap.sh`. Commit: `cache C/C++ objects and compile in parallel`.

### Task 4: Projects without a Zark entry, and Zark without `main`

**Files:**
- Modify: `selfhost/main.zk` (driver: the project branch near the top of `compile`, and the `has no 'main' function` check), `selfhost/project.zk` (`load_project` must not fail when `package.main` does not exist if `build.sources` is non-empty), `tests/cbuild.sh`

**Interfaces:**
- In a project whose `main` file does not exist and which lists at least one source: `zark build` compiles the sources and links them (`clang++` if any is C++) to `build/<name>` (or `build.out`); `zark run` does that and runs the result with the program arguments; `zark test` reports `no tests` with exit 0.
- A `.zk` file without `main` is accepted when `CSplit.sources` is non-empty; the linker reports a missing `main`.
- A project with neither a Zark `main` nor sources keeps today's error.

- [ ] **Step 1: Tests** `cpp_only_project` (manifest with `sources = ["src/app.cpp"]`, `std = "c++17"`, `libs = ["stdc++"]`; `zark run -- a b` prints the argv count) and `zark_lib_with_c_main` (main in C calls an `export`ed Zark function, Zark file has no `main`).
- [ ] **Step 2: Run, see them fail.**
- [ ] **Step 3: Implement.** Reuse `compile_sources` and the link code; do not duplicate the link command line, extract it if needed.
- [ ] **Step 4: Run `tests/cbuild.sh`, `tests/project.sh`, `./bootstrap.sh`.** Commit: `build projects without a Zark entry`.

### Task 5: `zark cbind`: preprocessing, C declaration parser, scalars, structs, typedefs, functions

**Files:**
- Create: `selfhost/cbind.zk`, `tests/cbind.sh`, `tests/cbind/scalars.h`, `tests/cbind/scalars.out`, `tests/cbind/structs.h`, `tests/cbind/structs.out`
- Modify: `selfhost/main.zk` (command `cbind`), `tests/run.sh`

**Interfaces:**
- Produces:
  - `struct CBind { str zk; str inline_c; List<str> deps; List<str> warnings; }`
  - `!CBind cbind_header(Allocator a, str header, str from_dir, List<str> flags)`: writes a stub `.zark-cache/cbind/stub-<pid>.c` with `#include "<header>"`, runs `clang -E -dD -iquote <from_dir> <flags> -x c <stub>` and captures stdout with `exec`; non-zero exit returns `error.CompileFailed` after printing clang's stderr. `deps` is every file named by line markers (`# <n> "<file>" <flags>`), excluding the stub.
  - Command `zark cbind <header> [compile flags] [-o out.zk]`: prints `CBind.zk` to stdout or the file, warnings to stderr.
- Declaration filter (spec "Which declarations"): relevant files are the first file named after the stub marker (the header), plus any file whose line-marker flags do not contain `3` or that sits in the same directory as the header.
- Mapping and output format, one declaration per line, in header order, exactly these shapes (these lines are the golden output):
  - `typedef unsigned int u32t;` → `type u32t = u32;`
  - `typedef struct P P;` with later `struct P { int x; double y; };` → `struct P { i32 x; f64 y; }` (the typedef of the same tag emits nothing extra)
  - `struct node { struct node* next; int v; };` → `struct node { node* next; i32 v; }`
  - incomplete `typedef struct W W;` never defined → `struct W { }`
  - nested anonymous struct member → emitted as a separate struct named `<outer>__anon<n>` (n counts from 0 per outer record) with the outer field referring to it, same layout
  - `int add(int a, int b);` → `extern i32 add(i32 a, i32 b);`; unnamed parameters become `a0`, `a1`; `void f(void)` → `extern void f();`; varargs → `extern i32 printf(u8* fmt, ...);`
  - `const char* s` → `u8* s`; `char` → `u8`; `unsigned char` → `u8`; `signed char` → `i8`; `_Bool` → `bool`; `size_t` → `usize`; `int8_t..uint64_t` → `i8..u64`; `T x[N]` field → `T[N] x`; array parameters decay to `T*`
  - function pointer typedef `typedef int (*cb_t)(void*, int);` → `type cb_t = fn(void*, i32) -> i32;`
  - names that are Zark keywords get `_` appended (`type` → `type_`); read the keyword list from `selfhost/lexer.zk`
  - skipped (warning `skipped <name>: <reason>` on stderr, exit 0): function-like macros, `long double`, `_Complex`, `_Atomic`, `extern` variables, flexible array members
- Parser notes: it tokenizes preprocessed text, skips function bodies and `__attribute__((...))`, `__asm__(...)`, `__extension__`, `__restrict`, `_Static_assert(...)` by bracket matching, keeps a typedef table for declarator disambiguation, and handles pointer/array/function declarators with parentheses.

- [ ] **Step 1: Write `tests/cbind/scalars.h`, `structs.h` covering every line above and the goldens `*.out`** (write the expected text by hand from the mapping, not from the tool's output). `tests/cbind.sh` runs `$ZARK cbind tests/cbind/NAME.h` and diffs against `NAME.out` for each, and also compiles each output (`$ZARK ir` on a file that imports it and defines `void main() {}`) to prove it is valid Zark.
- [ ] **Step 2: Run `tests/cbind.sh`**, see it fail (`unknown command cbind`).
- [ ] **Step 3: Implement** `cbind.zk` (tokenizer for C, declaration parser into a `CDecl` tree: `Func`, `Struct`, `Typedef`; type tree `CType` with kinds `Int(width, signed)`, `Float(width)`, `Bool`, `Void`, `Ptr`, `Array`, `Func`, `Named`; emitter) and the `cbind` command. Keep parser state in a struct with methods, like `selfhost/parser.zk`.
- [ ] **Step 4: Run `tests/cbind.sh`, `./bootstrap.sh`.** Commit: `add zark cbind for C declarations`.

### Task 6: Enums and macro constants

**Files:**
- Modify: `selfhost/cbind.zk`, `tests/cbind.sh`; Create: `tests/cbind/consts.h`, `tests/cbind/consts.out`

**Interfaces:**
- Produces in `cbind.zk`: `bool eval_const(CTokens expr, Consts* env, i64* out)` over integer constant expressions: literals (decimal, hex, octal, binary, `u/l/ul/ull` suffixes, char literals), unary `- + ~ !`, binary `* / % + - << >> < > <= >= == != & ^ | && ||`, `?:`, parentheses, references to earlier enumerators and earlier evaluated macros, `sizeof` of scalar types. Anything else (identifiers it does not know, casts of non-scalar types) fails evaluation.
- Output shapes (golden):
  - `enum E { A = 1, B, C = A + 4, D = -1 };` → `type E = i32;` then `const auto A = 1;`, `const auto B = 2;`, `const auto C = 5;`, `const auto D = -1;`
  - an enum with any value above `INT_MAX` or no negative value but a value `> INT_MAX` → `type E = u32;` (or `i64`/`u64` if needed)
  - anonymous enum → constants only
  - `#define N 42` → `const auto N = 42;`; `#define MASK (1u << 3)` → `const auto MASK = 8;`; `#define NAME "text"` → `const auto NAME = "text";`; `#define F 1.5` → `const auto F = 1.5;`; `#define SUM (N + MASK)` → `const auto SUM = 50;`; `#define C 'a'` → `const auto C = 97;`; `#define OBJ_ALIAS N` → `const auto OBJ_ALIAS = 42;`
  - skipped with a warning: function-like macros, macros that expand to non-constants or empty, macros defined or undefined inside the system headers, redefinitions with a different value
  - macros are taken from the `#define`/`#undef` lines of `-dD`, only from relevant files

- [ ] **Step 1: Write `consts.h` and `consts.out`** with the cases above plus negative values, `0xFFFFFFFFu`, `1UL << 40` (so `i64` const) and an enum referencing a macro; write the golden by hand.
- [ ] **Step 2: Run, see fail.** 
- [ ] **Step 3: Implement** `eval_const` and the enum/macro emission.
- [ ] **Step 4: Run `tests/cbind.sh`.** Commit: `bind C enums and macro constants`.

### Task 7: Unions, opaque records, record layouts

**Files:**
- Modify: `selfhost/cbind.zk`, `tests/cbind.sh`; Create: `tests/cbind/unions.h`, `tests/cbind/unions.out`, `tests/cbind/layout.h`, `tests/cbind/layout.out`

**Interfaces:**
- `!Layouts read_layouts(Allocator a, str stub, List<str> flags)`: runs `clang -fsyntax-only -Xclang -fdump-record-layouts -x c <flags> <stub>` and parses `*** Dumping AST Record Layout` blocks into a map from record name (`struct X`/`union X`) to `{ i64 size; i64 align; }` (from the `[sizeof=N, align=M]` line). Anonymous records use the block's own name text; if a name cannot be matched the record is skipped with a warning.
- Output shapes (golden):
  - `union U { int i; float f; double d; };` → `struct U { u64[1] storage; }` plus methods inside the struct: `i32* as_i() { void* p = this; return p; }`, `f32* as_f()`, `f64* as_d()`; storage element chosen by alignment (`u64` for align 8, `u32` for 4, `u16` for 2, `u8` for 1) and count `size / element size`; the exact text must compile (check with `zark ir`)
  - struct with a bitfield, `__attribute__((packed))`, `__attribute__((aligned(N)))` or `_Alignas` → `struct S { u8[SIZE] storage; }` when align is 1, else the same storage rule as unions, with no fields and a warning `opaque <name>: bitfields|packed|aligned`
  - a union or struct nested in a struct keeps its own generated type and the outer field refers to it
  - `sizeof` of every emitted struct must equal clang's `sizeof` (tested in Task 9)

- [ ] **Step 1: Write the headers and hand-written goldens**, including a nested anonymous union, an array of structs, and a self-referential struct (Review Focus 4).
- [ ] **Step 2: Run, see fail.**
- [ ] **Step 3: Implement** `read_layouts` and the union/opaque emission; detect attributes and bitfields in the parser (`: width` after a field, `__attribute__((packed|aligned))`, `_Alignas`).
- [ ] **Step 4: Run `tests/cbind.sh`.** Commit: `bind C unions and opaque records`.

### Task 8: `static inline` functions

**Files:**
- Modify: `selfhost/cbind.zk`, `tests/cbind.sh`; Create: `tests/cbind/inline.h`, `tests/cbind/inline.out`, `tests/cbind/inline.c.out`

**Interfaces:**
- `CBind.inline_c` holds a C file: `#include "<header>"` (the resolved absolute path of the named header) then one wrapper per relevant `static inline` (or `inline`) function with a representable signature: `R zark_inl_<name>(A a0, B a1) { return <name>(a0, a1); }` (`void` functions without `return`). The bindings emit for the same function: `R name(A a0, B a1) { return zark_inl_name(a0, a1); }` and `extern R zark_inl_name(A a0, B a1);`. Wrapper parameter types are written in the original C spelling taken from the source tokens of the declaration, so no type has to be re-spelled.
- Both files are golden-tested (`inline.out`, `inline.c.out`). The `zark cbind` command prints the C file when given `--inline-c <path>`.

- [ ] **Step 1: Write `inline.h`** (static inline functions taking and returning ints, pointers, a struct by pointer) and hand-written goldens.
- [ ] **Step 2: Run, see fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `tests/cbind.sh`.** Commit: `wrap static inline C functions`.

### Task 9: `import "header.h"` and the binding cache

**Files:**
- Modify: `selfhost/loader.zk` (`load_source` import loop, `import_target`), `selfhost/cbind.zk` (globals and `cbind_import`), `selfhost/main.zk` (set flags/cache, add generated C files to the sources), `tests/cbind.sh`; Create: `tests/cbind/interop/` (a C library `lib.c`, `lib.h`, `main.zk`, `main.out`)

**Interfaces:**
- In `cbind.zk`: globals `List<str> c_flags`, `str c_cache`, `List<str> c_inline_sources`; `!str cbind_import(Allocator a, str header, str from_dir)` returns the path of the cached `.zk` file `<cache>/cbind/<hash16>.zk` and, when the result has inline wrappers, writes `<hash16>.c` next to it and appends its path to `c_inline_sources` (once per path). The hash covers the resolved header path, the flags, the clang version line (`clang --version` first line) and the contents of all files in `deps`; the first call after a header edit regenerates. A cache hit reads a `<hash16>.deps` file (paths) and rehashes their contents instead of running the preprocessor. Writes use temp plus `mv`.
- In `loader.zk`: when `d.path` ends with `.h`, call `cbind_import` and load the returned file with the import's alias as prefix (`load_file(path, d.alias)`). The same header imported twice maps to one cache file, so the loader's existing "seen" handling applies.
- In `main.zk`: before loading, set `c_flags` from `CSplit.flags` and `c_cache`; after loading, append `c_inline_sources` to the source list that `compile_sources` compiles. C++ extensions (`.hpp .hh .hxx`) fail with `error: C++ headers are not supported yet (layer 4): <path>`. A missing header prints the directories searched (`clang -E -v` is not needed; list `from_dir`, each `-I`, and `/usr/include`).
- Interop test in `tests/cbind/interop/`: `lib.h` with a struct by value (`{ int x; double y; }`, x86-64 only part guarded by the script), an enum with explicit values, a macro constant, a union, a callback typedef, a `static inline`, a `const char*` return and a variadic `int sum_ints(int n, ...)`; `lib.c` implements them; `main.zk` does `import "lib.h" as lib;` and prints results; `main.out` holds the golden.

- [ ] **Step 1: Write the interop fixture and tests in `tests/cbind.sh`:** `import_basic` (run with `lib.c` and `-I`), `import_cache_hit` (a `clang` PATH shim counts invocations; the second run only invokes it for linking and compiling `lib.c`, not for `-E`), `import_header_edit` (change a macro value in `lib.h`, output changes), `import_twice` (two Zark files import the same header, one with an alias and one through a relative path; compiles and runs), `import_path_with_space` (header in a directory with a space), `import_cpp_header` (`.hpp` gives the C++ error and exit 1), `import_missing` (error names the searched dirs), `sizeof_matches` (a Zark program prints `sizeof(lib::T)` for every emitted struct and the C program prints the same numbers; compare).
- [ ] **Step 2: Run, see fail.**
- [ ] **Step 3: Implement** per Interfaces.
- [ ] **Step 4: Run `tests/cbind.sh`, `tests/cbuild.sh`, `./bootstrap.sh`, `FLAGS=--llvm ZARK=build/zark tests/run.sh`.** Commit: `import C headers`.

### Task 10: Dear ImGui example, docs, seed

**Files:**
- Modify: `examples/imgui/main.zk`, `examples/imgui/run.sh`; Delete: `examples/imgui/imgui.zk`, `examples/imgui/sdl.zk`; Create: `examples/imgui/zark.toml`; Modify: `SPEC.md` (section 8), `README.md` (one paragraph under the FFI part), the FFI page in `docs-src/pages` if it exists, `bootstrap/seed.ll.gz` via `tools/update-seed.sh`

**Interfaces:**
- `examples/imgui/zark.toml` lists `include` (`deps/cimgui`, `deps/cimgui/imgui`, `deps/cimgui/imgui/backends`), `defines` (`CIMGUI_USE_SDL2`, `CIMGUI_USE_OPENGL3`, `IMGUI_IMPL_API=extern "C"`), `std = "c++17"`, `sources` (the nine `.cpp` files), `pkg-config = ["sdl2"]`, `libs = ["GL", "stdc++"]`. `run.sh` shrinks to the dependency fetch plus `exec zark run -- "$@"`. `main.zk` does `import "cimgui.h" as ig;`, `import "SDL2/SDL.h" as sdl;`, `import "cimgui_impl.h" as impl;` and calls through them; `ImVec2` literals come from the generated structs. Warnings for skipped declarations are acceptable; the demo must look and behave as before.
- `SPEC.md` section 8 gains the flags, the manifest keys, the cache, `import "x.h"`, `zark cbind`, the mapping table and the limits (C only, SysV x86-64 aggregates by value, skipped constructs). Docs are English, plain, short.

- [ ] **Step 1: Migrate the example** and run it for 5 frames (`run.sh 5`, exit 0) and visually once (`spectacle`, as before); the hand-written declarations are gone.
- [ ] **Step 2: Update `SPEC.md`, `README.md`, the guide page.** Rebuild the guide (`node docs-src/build.js` with an absolute `ZARK=`; restore `docs/superpowers` with `git checkout -- docs/superpowers`).
- [ ] **Step 3: Full verification:** `./bootstrap.sh`, `ZARK=build/zark tests/run.sh`, with `FLAGS=--llvm` and `FLAGS=-O`; then `tools/update-seed.sh` and `./bootstrap.sh` once more. Commit seed separately: `update seed`. Push, open the PR, wait for all 11 CI jobs, fix anything red on Alpine/macOS/arm64 (Apple clang line-marker flags, `-MD` output, `pkg-config` absence).
- [ ] **Step 4: Commit** `use cbind in the ImGui example` and `document C interop`.
