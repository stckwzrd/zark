---
title: Projects and dependencies
order: 32.5
section: Interop and tools
description: zark new, the zark.toml manifest, C sources and libraries, path and git dependencies, zark test in a project
---

A single file is enough to start. When a program grows into several files, C code or other people's libraries, describe it in a `zark.toml` and `zark run`, `zark build` and `zark test` work without a file name.

```sh
zark new hello        # hello/zark.toml, hello/src/main.zk, hello/.gitignore
cd hello
zark run              # compiles src/main.zk and runs it
zark run -- --name me # arguments after -- go to the program
zark build --release  # writes build/hello
zark test             # the test blocks of src/main.zk and of every file in tests/
```

The commands find `zark.toml` in the current directory or any directory above it, so they also work from `src/sub/`. A file named on the command line (`zark run tools/gen.zk`) inside a project still gets the project's dependencies, C sources and libraries.

## `zark.toml`

```text
[package]
name = "app"
version = "0.1.0"
main = "src/main.zk"      # what run and build compile (default src/main.zk)
lib = "src/lib.zk"        # what `import "app"` loads in projects that depend on this one

[build]
sources = ["c/fast.c"]      # C or C++ files compiled and linked in
libs = ["ssl", "m"]         # linked as -lssl -lm
flags = ["-O"]              # default flags; the command line adds to them
out = "build/app"           # where zark build writes the program (default build/NAME)

[dependencies]
utils = { path = "../utils" }
json5 = { git = "https://github.com/someone/json5.zk", rev = "v1.2" }
```

The format is a small part of TOML: sections, `key = value`, strings, integers, booleans, lists and inline tables, and `#` comments. A mistake is reported with the line: `zark.toml:2: error: unterminated string`.

## Dependencies

A dependency is imported by its name:

```zark fragment
import "utils" as u;            // the dependency's lib file
import "utils/strings" as us;   // a file next to it (.zk may be left out)
```

- `path` dependencies point to a directory on disk.
- `git` dependencies are cloned into `.zark/deps/NAME` the first time a command needs them (`rev` is a tag or branch). Delete the directory to fetch again.
- A dependency with its own `zark.toml` brings its own dependencies, C sources and libraries along. Without a manifest, its lib file is `src/lib.zk` or `lib.zk`.
- Imports that start with `./` or `../` are always relative files, so a dependency name never hides them.

The language server reads the same manifest, so imports of dependencies are found in the editor too.
