---
title: Projects and dependencies
order: 32.5
section: Interop and tools
description: vibe new, the vibe.toml manifest, C sources and libraries, path and git dependencies, vibe test in a project
---

A single file is enough to start. When a program grows into several files, C code or other people's libraries, describe it in a `vibe.toml` and `vibe run`, `vibe build` and `vibe test` work without a file name.

```sh
vibe new hello        # hello/vibe.toml, hello/src/main.vibe, hello/.gitignore
cd hello
vibe run              # compiles src/main.vibe and runs it
vibe run -- --name me # arguments after -- go to the program
vibe build --release  # writes build/hello
vibe test             # the test blocks of src/main.vibe and of every file in tests/
```

The commands find `vibe.toml` in the current directory or any directory above it, so they also work from `src/sub/`. A file named on the command line (`vibe run tools/gen.vibe`) inside a project still gets the project's dependencies, C sources and libraries.

## `vibe.toml`

```text
[package]
name = "app"
version = "0.1.0"
main = "src/main.vibe"      # what run and build compile (default src/main.vibe)
lib = "src/lib.vibe"        # what `import "app"` loads in projects that depend on this one

[build]
sources = ["c/fast.c"]      # C or C++ files compiled and linked in
libs = ["ssl", "m"]         # linked as -lssl -lm
flags = ["-O"]              # default flags; the command line adds to them
out = "build/app"           # where vibe build writes the program (default build/NAME)

[dependencies]
utils = { path = "../utils" }
json5 = { git = "https://github.com/someone/json5.vibe", rev = "v1.2" }
```

The format is a small part of TOML: sections, `key = value`, strings, integers, booleans, lists and inline tables, and `#` comments. A mistake is reported with the line: `vibe.toml:2: error: unterminated string`.

## Dependencies

A dependency is imported by its name:

```vibe fragment
import "utils" as u;            // the dependency's lib file
import "utils/strings" as us;   // a file next to it (.vibe may be left out)
```

- `path` dependencies point to a directory on disk.
- `git` dependencies are cloned into `.vibe/deps/NAME` the first time a command needs them (`rev` is a tag or branch). Delete the directory to fetch again.
- A dependency with its own `vibe.toml` brings its own dependencies, C sources and libraries along. Without a manifest, its lib file is `src/lib.vibe` or `lib.vibe`.
- Imports that start with `./` or `../` are always relative files, so a dependency name never hides them.

The language server reads the same manifest, so imports of dependencies are found in the editor too.
