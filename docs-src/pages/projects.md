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
include = ["c/include"]     # -I for C sources and imported headers; also defines, std, cflags, lib-dirs, pkg-config (see C interop)
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
- `git` dependencies are cloned into `.zark/deps/NAME` the first time a command needs them (`rev` is a tag, a branch or a commit); when `zark.lock` lists the dependency, its tree is checked out at the locked commit.
- A dependency with its own `zark.toml` brings its own dependencies, C sources and libraries along. Without a manifest, its lib file is `src/lib.zk` or `lib.zk`.
- Imports that start with `./` or `../` are always relative files, so a dependency name never hides them.

### Locking and updating

A `git` dependency is recorded in `zark.lock` next to `zark.toml`: the URL, the requested `rev`, and the exact commit it resolved to. `zark build`, `run`, `test` and the language server use that commit, so a branch or a tag that moves does not change what you build.

```sh
zark update              # resolve every git dependency again and rewrite zark.lock
zark fetch               # put the locked commits into .zark/deps (no resolution; for CI and offline)
zark add URL [--rev R]   # add a git dependency to zark.toml and lock it
zark remove NAME         # drop a dependency from zark.toml and zark.lock
```

- `zark update` is the only command that moves a dependency to a new commit; it also replaces the entry when you change `rev` in `zark.toml`.
- If `zark.toml` asks for a `rev` that `zark.lock` does not have, or the fetched tree is not at the locked commit, the build stops and asks for `zark update`.
- One name is one source and one commit: reaching it with two different `rev` values, or from two different git URLs, is an error.
- `path` dependencies are not locked; they are edited in place.
- Commit `zark.lock`: it is what teammates and CI build.

The language server reads the same manifest, so imports of dependencies are found in the editor too.
