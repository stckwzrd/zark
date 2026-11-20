---
title: How it all works
order: 43
section: Reference
description: How the Vibe compiler is built: the pipeline, the backends, self-hosting, the memory layout of types and the plans for the future
---

This page is for those who want to understand what happens under the hood, or who are going to change the compiler. It is not required for writing programs.

## The pipeline

The compiler is a program in Vibe itself, about 12 thousand lines in the `selfhost/` directory. It works as a pipeline:

```text
source .vibe
   │
   ▼  lexer.vibe      tokens
   ▼  parser.vibe     recursive descent → a tree (ast.vibe), string interpolation is parsed here
   ▼  loader.vibe     loading import, module prefixes (resolve.vibe)
   ▼  gen*.vibe       type checking, monomorphization of generics, LLVM IR text
   │
   ├── by default:    native.vibe + x64.vibe   IR → x86-64 machine code → ELF .o
   └── -O / --release / --llvm:                IR → clang (LLVM) → .o
   ▼
linking through clang (together with .c, .cpp, .o) → an executable
```

What each file does:

| File | Role |
|---|---|
| `lexer.vibe` | tokens (see [lexical structure](lexical.md)) |
| `ast.vibe` | "fat" tree nodes with a kind tag |
| `parser.vibe` | parsing the syntax, splitting `"{x}"` into parts |
| `gen.vibe` | types, instantiating generics, functions, diagnostics |
| `gen_stmt.vibe` | statements, `defer`/`errdefer`, `match` |
| `gen_expr.vibe` | expressions, addresses, operators, casts |
| `gen_call.vibe` | calls, inferring type parameters, methods, function pointers |
| `gen_fmt.vibe` | building `Fmt` for calls with interpolation, `panic`, `assert`, `embed` |
| `resolve.vibe`, `loader.vibe` | imports and module prefixes |
| `native.vibe` | the own backend: IR → x86-64 (System V ABI), register allocation |
| `x64.vibe` | the instruction encoder and the ELF64 object writer |
| `fmt.vibe` | the `vibe fmt` formatter |
| `lsp.vibe`, `ide.vibe`, `analysis.vibe`, `json.vibe`, `textpos.vibe` | the language server |
| `diag.vibe` | nice error messages, "did you mean" |
| `main.vibe` | the command-line driver |

You can see the intermediate results right from the CLI: `vibe tokens file.vibe` (tokens) and `vibe ir file.vibe` (LLVM IR). More in [tooling](tooling.md#intermediate-representations).

The prelude (`std/std.vibe`) is built into the compiler through `embed`, so `vibe` is one executable without external data.

## Two backends

**The own one (default).** It parses the textual LLVM IR that the frontend generated and turns it into x86-64 machine code. It uses linear-scan register allocation, fusing a comparison with a branch, constants in operands, and lazy loading of composite values. There is not a single line of LLVM inside. The purpose is a fast build: a typical project builds in fractions of a second.

**LLVM (`-O`, `--release`, `--llvm`).** The same IR is handed to `clang`, which does full optimization. It is needed for speed in production builds.

A comparison for a program of 10 thousand lines, from source to executable (the author's measurements):

| Builder | Time |
|---|---|
| vibe, own backend | about 95 ms |
| clang -O0 | about 220 ms |
| gcc -O0 | about 670 ms |

And the speed of the result (recursive `fib(38)` and a sieve of 50 million):

| | fib(38) | sieve 50M |
|---|---|---|
| C (`clang -O2`) | 97 ms | 369 ms |
| Vibe `--release` | 95 ms | 345 ms |
| Vibe, own backend | about 290 ms | about 820 ms |

So `--release` does not lose to C, and the debug build wins in compile speed.

## Self-hosting and the fixed point

The compiler builds itself. To start from zero, the repository holds a **seed**: the LLVM IR of the compiler itself (`bootstrap/seed.ll.gz`). `clang` turns it into the first working compiler.

```text
seed (clang)  →  stage1 (Vibe, built from the seed)
              →  stage2 (Vibe, built by stage1)
              →  stage3 (Vibe, built by stage2)
```

The check: **stage2 and stage3 are identical byte for byte** (the fixed point). The same is done for the chain with the own backend without LLVM (native2 == native3). The script `bootstrap.sh` runs everything, then runs the test suite and puts the result into `build/vibe`.

A consequence for development: a new language feature is added in two steps. First the compiler is taught the feature without using it in its own sources, and the seed is updated (`tools/update-seed.sh`). Only then can the feature be used in `selfhost/`: otherwise the old seed cannot build the new code.

## The memory layout of types

The principle "what you see is what is in memory":

| Type | In memory |
|---|---|
| `i8..i64`, `u8..u64` | an integer of the corresponding size |
| `bool` | one byte |
| `T*` | a pointer, 8 bytes |
| `T[]`, `str` | `{ ptr, len }`, 16 bytes |
| `T[N]` | `N` elements in a row |
| `struct` | the fields in order, alignment as in C |
| `enum` | a 32-bit integer |
| `union` | `{ i32 tag, payload }`, the payload sized for the largest variant |
| `!T` | `{ i32 error code, T }` |
| `fn(A) -> R` | a function pointer |
| `fn[](A) -> R` | a pair: a function pointer and a context pointer |

This explains why structs can be passed to C (by pointer), why nothing needs to be "packed" at a call and why `sizeof` is predictable.

## How interpolation is expanded

The compiler knows neither `print` nor `println`. It knows one rule: if the last parameter of the called function has the type `Fmt` (declared in `std/std.vibe`), all the remaining arguments and strings with `{...}` are gathered into a `Fmt` value.

`Fmt` is a list of pieces: literal text, a pointer to a value, a function that knows how to print a value of that type, and a specification (`:08X`, `:.2` and so on). The print functions for structs, enums, unions and arrays are generated by the compiler from the type as ordinary Vibe code. For numbers, strings and pointers the functions from the prelude are used (`__fmt_int`, `__fmt_str` and others).

Everything lies on the caller's stack, and nothing is allocated on the heap. So interpolation is allowed where there is a function with a `Fmt` parameter: `print`, `println`, `eprint`, `eprintln`, `panic`, `bprint`, `sprint` and your own.

## How generics work

Functions and structs with type parameters are **monomorphized**: for each combination of arguments the compiler creates a separate copy. So there is no run-time overhead, and the body of a generic is checked at the **use**. Constraints (`T: Ord`) are checked at the call, before the body is compiled, so that the message is clear.

## How `defer` and `errdefer` work

The compiler expands `defer` into code **on every path out of** the block: before `return`, `break`, `continue` and at the end of the block. For `errdefer` the code is added only on the paths where an error is returned. There is no run-time machinery for this.

## How `?` and `catch` work

`f()?` turns into a check of the error code: if it is not zero, `defer` and `errdefer` run and the same `!T` is returned. `catch` is the same check, but instead of returning it takes the branch with the fallback value.

## Lazy compilation

Only the functions **reachable from `main`** are compiled. An extra import does not bloat the file, and errors in dead code are not visible until it is called (unless it is a generic: then the error shows up on the first use).

## Build storage

Intermediate files live in `.vibe-cache/` next to the place where you run the compiler: `.o`, `.ll` and test binaries. The directory can be deleted at any time.

## The compiler's own tests

In `tests/`:

- `tests/run.sh` runs the examples from `examples/` and compares the output with `tests/expected/`;
- `tests/errors/` holds programs that **must** fail to compile;
- a check that the tokens of the examples match the reference files in `tests/tokens`;
- a check of the fixed point.

The build modes are checked by the same tests: `FLAGS=--llvm` and `FLAGS=-O` run them through LLVM.

## What next

Known directions of development (more in `ROADMAP.md`):

- **The quality of the backend's code.** Debug builds are roughly three times slower than gcc -O0. Next: SSA without `alloca` in the frontend and an in-memory internal representation instead of the textual IR.
- **An own linker** and a runtime without libc on Linux system calls: so that pure Vibe programs build without external tools.
- **`comptime`:** running Vibe at compile time for tables and code generation; `inline for`.
- **`@cImport`:** parsing C headers and passing structs by value across the C boundary.
- **Overflow checking on by default** in the safe mode (the opt-in flag `--check-overflow` already exists).
- **New platforms:** aarch64 and Windows.
- **Tools:** DWARF for local variables and types (the line table is already there).

These are plans, not promises: the language grows to the needs of its author.
