# Contributing to Zark

Thanks for taking the time to help. This page describes how the project is run, how to
build and test it, and what a good change looks like.

Zark is **alpha** and currently in a *stability* phase: the language and the syntax are
frozen. New features are not accepted right now. Bug fixes, tests, diagnostics,
documentation, portability fixes and performance work are.

## Before you start

- Read [INSTALL.md](INSTALL.md) and build the compiler once with `./bootstrap.sh`.
- Read [SPEC.md](SPEC.md), at least sections 11 and 12: they list what the compiler does
  not check and what is undefined or implementation-defined.
- Look at the open issues. Labels say what kind of work it is: `bug`, `soundness`,
  `crash`, `miscompile`, `diagnostics`, `docs`, `platform`, `speed`.

## Reporting a bug

A useful report has four things:

1. **A minimal program** that shows the problem (a few lines, not a whole project).
2. **The command** and the flags (`zark run x.zk`, `zark ir x.zk --arch aarch64`, …).
3. **What you expected and what happened** — paste the compiler output, not a screenshot.
4. **The platform**: OS and distribution, architecture, `clang --version`, `zark --version`
   if the build has it.

If the compiler crashes, the report is much easier to act on when it includes the output of
the crash handler (the backtrace it prints). If the problem is a wrong result, say which
backend was used: the default (native, x86-64 Linux), `--llvm`, `-O` or `--release` — a
difference between them is itself a valuable clue.

## Fixing a bug

The project follows one rule: **a bug fix comes with a test that fails before the fix.**
The sequence is:

1. Open (or pick) an issue with a minimal repro.
2. Add the repro to the suite, in the place that matches its kind:
   - `tests/errors/` — the program must be rejected; add `name.zk` and `name.err` with the
     expected first non-empty line of the diagnostic (without the `file:line:` prefix).
   - `tests/edge/` — a program that must compile and run; add its expected output under
     `tests/expected/` if the runner compares stdout.
   - `tests/panics/` — the program must stop with a panic; the expected text goes to
     `tests/expected/`.
   - `tests/cbind/`, `tests/cxxbind/` — header binding goldens.
   - `tests/crash/` — the crash handler and backtraces.
3. Run the new test and watch it fail for the right reason.
4. Fix the compiler (or the standard library, or the test infrastructure).
5. Run the whole suite (below).
6. Commit with the issue number: `fix the empty interpolation panic (fixes #69)`.
7. Open a pull request. A maintainer merges it after the suite is green; the issue is
   closed by hand if the automatic close did not fire (it does not for non-default branches).

Do not "fix" a test by changing its expected output unless the old output was wrong. If a
diagnostic really has to change, say why in the commit and update the `.err` file in the
same commit.

## Building

```sh
./bootstrap.sh          # seed -> stage1 -> stage2 -> stage3, native chain, tests, build/zark
```

The script stops at the first failed check and does not install a broken compiler. For a
quick rebuild while working on the compiler itself, `build/stage2 build selfhost/main.zk
--release -o build/zark` is enough — the full bootstrap is for validating a fixed point.

## Running the tests

The full matrix on one machine:

```sh
ZARK=build/zark tests/run.sh            # native backend
ZARK=build/zark tests/run.sh --llvm     # LLVM, no optimization
ZARK=build/zark tests/run.sh -O         # LLVM -O2, bounds checks on
tests/cbind.sh                          # C headers (uses build/zark by default)
tests/cxxbind.sh                        # C++ headers
ZARK=build/zark tests/baremetal.sh      # boots the kernel in QEMU, if installed
```

Under the sanitizers (Linux):

```sh
tools/build_asan.sh
ZARK=build/zark-asan tests/run.sh
tools/fuzz_prog.py --count 10000
tools/fuzz_crash.py --count 100000
tools/fuzz_lsp.py --count 2000
tools/fuzz_own.py --count 300
```

Notes for contributors on Fedora and other distributions:

- If `clang` is a ccache wrapper (`/usr/lib64/ccache/clang`), the test shims resolve the
  real compiler themselves (`tests/compiler.sh`); do not "fix" a hang by deleting the
  shim.
- `tests/scale.sh` and ASan runs lift `RLIMIT_AS`; keep that behaviour when adding tests
  that start many processes.
- The full suite is deliberately part of `./bootstrap.sh`. A change that makes the suite
  slow enough to be annoying is a regression too.

## Style

- Match the surrounding code. The compiler is written in Zark itself and follows the
  language's own rules: explicit allocators, `defer`, no hidden allocation.
- Keep a change focused. Formatting-only edits and unrelated renames make review harder.
- Diagnostics are user-facing text: write them as a sentence, keep the `file:line:` prefix
  out of the `.err` files, and include a hint when there is an obvious fix
  (`did you mean 'push'?`).
- The compiler must stay deterministic: the same input must produce byte-identical IR and
  binaries, with any `ZARK_JOBS` value. `tests/determinism.sh` checks this.

## Documentation

The guide's sources are in `docs-src/pages/` (English) and `docs-src/pages-ru/` (Russian);
the generated HTML in `docs/` is committed. After editing a page:

```sh
cd docs-src
npm install          # once
node build.js        # runs every code block with ../build/zark and writes ../docs
```

If a page has a `zark run` block, the build executes it and inserts the real output, so an
example that stops compiling fails the build. `tests/docs.sh` does the same into a
temporary directory as part of the suite.

Keep the two languages in sync when you change an explanation; a translation that says
something different from the English page is worse than no translation at all.

## Commits and pull requests

- One logical change per commit. A commit message says what changed and why, in the
  imperative: `reject a call after the captured variable was consumed`.
- Reference the issue in the last line: `(fixes #42)`.
- A pull request description should contain: the problem, the repro, the fix and the tests
  that cover it. Screenshots are not needed for compiler work; pasted output is.
- Branches are merged into `main` after the suite is green. The `language-fixes` branch is
  the current integration branch for the stability work.

## License

By contributing you agree that your changes are dual licensed under Apache-2.0 and MIT, as
described in [README.md](README.md#license).
