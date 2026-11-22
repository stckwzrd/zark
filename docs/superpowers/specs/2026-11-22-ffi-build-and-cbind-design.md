# C/C++ build integration and `import "header.h"` design

Layers 1 and 2 of the FFI work. Layer 3 (strict C ABI: `export` with aggregates by value, AArch64, Win64, ABI fuzzing) and layer 4 (C++ through generated `extern "C"` shims) are separate projects.

## Why

Zark's FFI speaks the C ABI, and that part works. What does not work is everything around it: using a real C library means hand-writing every `extern` and struct, and building the C/C++ side has no include paths, no defines, no object cache. The Dear ImGui example needed a shell script to build the library and about 80 hand-written declarations. The goal is that using SDL, sqlite, zlib or curl from Zark costs a manifest entry and one `import` line, and that a C/C++ application (with or without Zark code in it) builds with `zark build`.

## Goals

1. C/C++ compile flags (`-I`, `-D`, `-std=` and friends) from the command line and from `zark.toml`, and `pkg-config` support.
2. A content-addressed object cache for C/C++ sources, parallel compilation, correct rebuild when a header changes.
3. A project that has C/C++ sources and no Zark entry file (or a Zark file without `main`) builds and runs.
4. `import "header.h" [as name];` generates Zark declarations from a C header: functions, structs, unions, enums, typedefs, simple macro constants, function pointers, varargs, `static inline` functions.
5. `zark cbind header.h [flags] [-o out.zk]` prints the same bindings, for inspection or for vendoring them.
6. Everything we cannot represent exactly is left out with a warning on stderr. A wrong binding is worse than a missing one.

## Non-goals

- C++ headers (classes, templates, overloads, namespaces). `import` of a C++ header is an error that says so. Layer 4.
- Fixing the ABI gaps (`export` with aggregates by value, AArch64 aggregates by value, `long double`). Layer 3. The bindings inherit today's limits and document them.
- Replacing clang. The `clang` that Zark already needs for `rt.c`, the LLVM path and linking is the only tool used.
- A package registry or version solving.

Anti-goal: a binding generator that sometimes emits a struct with the wrong layout. Layout correctness beats coverage.

## Approaches considered for reading headers

- **clang AST as JSON** (`-Xclang -ast-dump=json`): exact, but measured at 256 MB and 3 s for `SDL2/SDL.h` (the JSON repeats ranges and bodies of every inline function). Even with `-ast-dump-filter` it is 41 MB. Rejected on size and speed.
- **clang AST as text**: 22 MB, 1.5 s, and the format is ad hoc per node kind and delta-encodes file names. Fragile across clang versions (the CI has 11 environments, Debian to Arch to Apple clang). Rejected.
- **libclang through `dlopen`**: the best data (sizes, offsets, bitfields, macro values for free). Rejected for now: libclang is a separate package on several distributions with versioned names, and its visitor callback passes a 32-byte `CXCursor` by value into a Zark function, which is exactly the `export` ABI gap of layer 3.
- **clang as a preprocessor plus a declaration parser in Zark (chosen)**: `clang -E -dD` on `SDL.h` takes 0.23 s and gives 2.7 MB with `#define`s and `# line "file" flags` markers. A C declaration parser that skips function bodies and attributes by bracket matching is small (typedefs, struct/union/enum, prototypes, declarators) and stable across clang versions. Sizes of the few records Zark cannot lay out itself come from `clang -fsyntax-only -Xclang -fdump-record-layouts`, whose `sizeof=`/`align=` lines are stable.

## Layer 1: build integration

**Flags.** Any extra argument starting with `-I`, `-isystem`, `-D`, `-U`, `-std=`, `-include`, `-f`, `-W` (but not `-Wl,`), or `-pthread` is a compile flag, passed to every C/C++ compile and to header preprocessing. `-l`, `-L`, `-Wl,`, `.o`, `.a`, `.so` stay link arguments as today.

**Manifest.** In `[build]`:

```toml
include = ["deps/imgui", "deps/cimgui"]
defines = ["CIMGUI_USE_SDL2", "IMGUI_IMPL_API=extern \"C\""]
std = "c++17"
cflags = ["-fno-exceptions", "-fno-rtti"]
pkg-config = ["sdl2"]
libs = ["GL", "stdc++"]
lib-dirs = ["/opt/foo/lib"]
```

`pkg-config = [...]` runs `pkg-config --cflags --libs` once per project and distributes the result into compile flags and link arguments. A missing `pkg-config` or package is an error with the package name in the message. Dependencies contribute their `include`, `defines`, `pkg-config`, `sources`, `libs` as they already contribute `sources` and `libs`.

**Object cache.** Each C/C++ source compiles to `.zark-cache/obj/<base>-<hash>.o`. The hash covers the compiler name, the optimization level, all compile flags, the source text, and the contents of every header listed by the dependency file (`-MD -MF`) from the previous compile. Two sources with the same base name no longer collide. A hit costs one stat and hash pass, no compiler run. Compiles run in parallel (`ZARK_JOBS`, same default as the native backend); output order and link order stay deterministic.

**No Zark entry.** In a project, `main` may be missing. If the project lists at least one source, `zark build` and `zark run` skip the Zark compile and just compile and link the sources (`clang++` if any is C++). If the Zark file exists but has no `main`, the "has no 'main' function" error is dropped when at least one C/C++ source is given: the linker reports a missing `main` if there really is none.

## Layer 2: `import "header.h"`

**Syntax.** No parser change. The loader sees an import path ending in `.h` and treats it as a C header. `import "SDL2/SDL.h" as sdl;` gives `sdl::SDL_Init(...)`; without `as`, names are global. The header is resolved the way the C compiler resolves `#include "..."`: next to the importing file, then the `-I` directories, then the system directories. Resolution is done by clang itself on a generated stub, and the resolved path is taken from the first line marker.

**Which declarations.** A declaration is emitted if it comes from the named header, or from a header it includes that is not in a default system directory (a file with the `3` flag in the line markers) or that sits in the same directory as the named header. That puts `/usr/include/SDL2/*.h` in (it comes in through `-I`) and the libc headers out. Types that emitted declarations refer to are resolved even when they come from elsewhere: the standard integer typedefs map to Zark integers, `size_t` to `usize`, `FILE` and other incomplete records become opaque.

**Mapping.**

| C | Zark |
|---|---|
| `char`, `signed char`, `unsigned char` | `u8`, `i8`, `u8` (`char*` is `u8*`) |
| `short`, `int`, `long`, `long long` and unsigned forms | `i16 i32 i64 i64`, `u16 u32 u64 u64` (LP64 only) |
| `float`, `double` | `f32`, `f64` |
| `_Bool` | `bool` |
| `T*`, `const T*` | `T*` (const dropped), `void*` stays `void*` |
| `T[N]` field | `T[N]` |
| `typedef X Y` | `type Y = X;` |
| `struct S { ... }` | `struct S { ... }` with the same field order, so the same layout |
| incomplete `struct S` | `struct S { }`, used only behind pointers |
| `enum E { A = 1, B }` | `type E = i32;` (`u32` if any value does not fit) and `const auto A = 1;`; values are evaluated by the parser, including expressions over earlier enumerators and literals |
| `union U { ... }` | `struct U` with storage of the right size and alignment (an array of `u64`, `u32` or `u8`) and a method `as_<member>()` per member that returns a pointer to that member's type |
| function pointer | `fn(A, B) -> R` |
| `R f(A, ...);` | `extern R f(A, ...);` |
| `static inline R f(A)` | a generated C file `zark_inline_<hash>.c` with `R zark_inl_f(A) { return f(A); }`, compiled and linked by the driver, and `R f(A a) { return zark_inl_f(a); }` in the bindings |
| `#define N 42`, `0x10`, `1.5`, `"text"`, `(1 << 3)`, `A | B` | `const auto N = ...;` (evaluable object-like macros only) |

Field and parameter names that are Zark keywords (`type`, `match`, ...) get a trailing underscore. Function-like macros, bitfield members, flexible array members, `_Atomic`, `_Complex`, `long double` and variables (`extern int x;`) are skipped with a warning; a struct with bitfields, `packed`, or `aligned` attributes is emitted as an opaque storage struct of the exact `sizeof`/`align` read from `-fdump-record-layouts`, without its fields. A function whose signature uses a skipped type is skipped too. Struct by value to and from C follows today's limits (System V x86-64 only).

**Cache.** Bindings are cached in `.zark-cache/cbind/<hash>.zk`, keyed by the same header closure hash as the object cache, the flags, and the clang version string. A hit costs a stat pass.

**`zark cbind`.** `zark cbind header.h [compile flags] [-o out.zk]` writes the bindings that `import` would use to stdout or to the file, with the skipped declarations listed on stderr.

**Errors.** A header that clang cannot preprocess reports clang's message. A C++ header (extension `.hpp`, `.hh`, `.hxx`, or `-x c++`) reports that C++ is not supported yet. A missing header names the directories that were searched.

## Testing

- Fixture headers under `tests/cbind/` covering each mapping row, each with a small C implementation; Zark programs call through the bindings and print results; golden outputs for the program and for `zark cbind`.
- The Dear ImGui example moves to a manifest plus `import "cimgui.h"` and loses its hand-written declarations and its build script (manual acceptance, SDL and OpenGL are not on CI).
- Project tests for flags, manifest fields, object cache hit and rebuild after a header edit, same-base-name sources, parallel compile determinism, C++-only project, missing `pkg-config` package.
- All existing checks still pass on all 11 CI jobs. Parts that need x86-64 struct-by-value stay x86-64 only.

## Calls made by the author

- The `import "x.h"` spelling instead of a new keyword, so no seed round trip is needed.
- Enums become integer typedefs plus constants rather than Zark `enum`s: C enums are open sets of integers and Zark enums are closed.
- Unions become storage structs with accessor methods, because Zark's `union` is tagged.
- Keyword clashes get a trailing underscore instead of changing the parser.
- Own declaration parser instead of the clang AST (see the approaches above).

## Left to the builder

The exact hash function, the temporary file naming, the job pool reuse for compile jobs, the warning wording, the parser structure inside `selfhost/cbind.zk`, and where the build logic lives (`selfhost/cbuild.zk` is suggested so that `main.zk` shrinks rather than grows).
