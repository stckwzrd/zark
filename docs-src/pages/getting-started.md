---
title: Installation and the first program
order: 1
section: Start
description: How to build the Vibe compiler, run a first program and understand the basic commands
---

Vibe is distributed as source code. The compiler is written in Vibe itself, so it has to be built once through a bootstrap chain. After that it builds itself and is developed with itself.

## What you need

| What | Why | Version |
|---|---|---|
| `clang` | linking finished binaries, building `.c`/`.cpp` files, the `-O`/`--release` modes | 18 or newer |
| `git` | to get the sources | any |
| `bash`, `gzip` | the `bootstrap.sh` script | any |

No separate starting compiler is needed. The repository contains a "seed" (`bootstrap/seed.ll.gz`): the Vibe compiler written as LLVM IR. `clang` builds the first version from it, and after that the compiler builds itself.

## Building the compiler

```sh
git clone https://github.com/stckwzrd/vibe.git
cd vibe
./bootstrap.sh
```

The script runs the whole chain and checks the result:

1. builds the first compiler from the seed with `clang`, and with it `stage1` from the sources in `selfhost/`;
2. builds `stage2`, a compiler built by the previous one, and `stage3`, once more; checks that `stage2` and `stage3` are byte-for-byte identical (the fixed point);
3. builds the chain without LLVM, `native1`, `native2`, `native3`, and checks that `native2 == native3`;
4. runs the whole test suite with the new compiler;
5. copies the result to `build/vibe`.

It takes about a minute. At the end you will see the line `== done: build/vibe is the self-hosted compiler`.

> **Warning:** if something in the script does not match (the fixed point is broken, a test fails), it stops with exit code 1 and copies nothing to `build/vibe`. Such a compiler must not be used.

## Putting `vibe` on your PATH

The simplest way is a link in a directory that is already on `PATH`:

```sh
mkdir -p ~/.local/bin
ln -sf "$PWD/build/vibe" ~/.local/bin/vibe
vibe        # prints the help
```

The link points at the file `build/vibe`, so every new `./bootstrap.sh` is picked up automatically.

## The first program

Create a file `hello.vibe`:

```vibe run
void main() {
    println("Hello, Vibe!");
}
```

Run it with `vibe run hello.vibe`. The compiler reads the file, generates machine code, links an executable into `.vibe-cache/hello` and runs it right away.

What matters here:

- a program starts at the function `main`; without it you get a library that cannot be run;
- `println` prints its arguments and a newline; inside a string, `{...}` evaluates an expression (**interpolation**, see [strings](strings.md));
- every statement ends with a semicolon, as in C++ ([lexical structure](lexical.md#end-of-a-statement)).

## Commands

```sh
vibe run   file.vibe [extra.c|.cpp|.o ...] [-O] [-- program arguments]
vibe build file.vibe [extra.c|.cpp|.o ...] [-o output] [-O] [--release]
vibe test  file.vibe [extra.c|.cpp|.o ...] [-O]
vibe fmt   [--check] file.vibe ...
vibe ir    file.vibe
vibe tokens file.vibe ...
vibe lsp
```

| Command | What it does |
|---|---|
| `run` | compiles and runs at once; everything after `--` goes to the program as arguments |
| `build` | compiles and leaves an executable in the current directory (by default the file name without `.vibe`) |
| `test` | runs the `test "..." { }` blocks ([tests](testing.md)) |
| `fmt` | brings files to one style ([tooling](tooling.md#vibe-fmt)) |
| `ir` | prints the LLVM IR produced by the frontend |
| `tokens` | prints the tokens (handy when debugging the lexer) |
| `lsp` | starts the language server for an editor |

### Program arguments

Everything after `--` is passed to the program. Inside it you have `arg_count()` and `arg(i)`. Argument zero is the path of the program itself, as in C:

```sh
$ vibe run args.vibe -- a "b c"
hello, 3 args
arg 0: .vibe-cache/args
arg 1: a
arg 2: b c
```

(`args.vibe` is a program that prints `arg_count()` and every `arg(i)`.)

### Exit code

- `void main() { ... }` gives code 0;
- `i32 main() { return 7; }` gives code 7 (`vibe run` returns the program's code);
- `!void main() { return error.Boom; }` prints `error: Boom` to stderr and returns 1;
- `panic("...")` and an out-of-bounds access print a message like `panic: ... (file:line)` and return 1.

## Compiler flags

| Flag | Meaning |
|---|---|
| (default) | the own x86-64 backend without LLVM: the fastest build |
| `--native` | choose the own backend even if `-O` is given (then `-O` has no effect) |
| `--llvm` | the LLVM backend without optimizations |
| `-O` | LLVM `-O2`; bounds checks stay |
| `--release` | `-O2` with the bounds checks removed |
| `--no-safety` | remove the bounds checks without enabling optimizations |
| `--fast-math` | `--fast` plus permission to reorder floating-point operations (`fast` on `fadd`, `fmul` and so on, like `-ffast-math`): sums and products can be vectorized, but results may differ slightly |
| `--check-overflow` | checks `+`, `-` and `*` for overflow even in a `--release` build (a safe build always checks your code; the prelude is not checked) |
| `--fast` | `--release` plus the assumption that signed overflow does not happen (`nsw`, as in C++): sometimes faster on integer loops, but the behavior is undefined on overflow |
| `-g` | own backend only: keep every local variable in memory and describe it for gdb (`print x`, `info locals`); slower code |
| `--time` | print the time of the frontend, the backend and the link |
| `-o name` | the name of the output file |
| `-- ...` | arguments for `vibe run` |

The build time of a small program looks like this (values depend on the machine):

```sh
$ vibe build hello.vibe --time -o t1
time: frontend 2.9 ms, native backend 0.3 ms, link 98.9 ms
$ vibe build hello.vibe --llvm --time -o t2
time: frontend 3.0 ms, llvm backend 0.1 ms, link 156.6 ms
```

Almost all the time goes into linking with `clang`. More about choosing a mode: [tooling](tooling.md#compilation-modes).

## What appears on disk

- `.vibe-cache/` in the current directory: object files (`name.o` for the own backend, `name.ll` for LLVM), the `.o` files of external C files and the executable for `vibe run`. The directory can be deleted at any time. Add it to `.gitignore`.
- `vibe build` creates the executable in the **current directory** (the file name without `.vibe`, or whatever `-o` says).

## Project layout

A single file is enough for a small program. When it grows, split it into modules ([modules](modules.md)):

```text
project/
  main.vibe        # fn main, import "geometry.vibe"
  geometry.vibe
  util/
    strings.vibe
```

Paths in `import` are relative to the directory of the file that contains the `import`.

## Editor

For VS Code / code-oss there is an extension with syntax highlighting, errors right in the editor, completion and go to definition. Installation and the setup for other editors are described on the [tooling](tooling.md#language-server-and-editor) page.

## What next

Open the [quick tour](tour.md): in a few minutes you will see the whole language. Then go through the "Language" section in order: each page covers one topic in detail.
