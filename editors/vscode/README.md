# Zark for VS Code

Language support for [Zark](../../README.md): syntax highlighting, snippets, the compiler's
language server, and commands to run, test, build and format a file.

## Install

The extension talks to the `zark` compiler, so build it once (from the repository root):

```sh
./bootstrap.sh          # produces build/zark
```

Then install the extension. From this directory:

```sh
npm install             # once; installs vscode-languageclient
python3 pack.py         # writes zark-lang-0.3.0.vsix
code --install-extension zark-lang-0.3.0.vsix
```

Or run `code --install-extension` on the `.vsix` that was built for you. VS Code 1.82 or
newer is required.

The extension finds the compiler in this order:

1. `zark.path`, if it is set;
2. `build/zark` in the workspace (the repository's own compiler);
3. `zark` on `PATH`;
4. `~/.local/bin/zark`, `/usr/local/bin/zark`, `/usr/bin/zark`.

If the server cannot start, the status bar shows a warning and the **Zark** output channel
contains the paths that were tried. Set `zark.path` or put the compiler on `PATH`.

## What it does

- **Highlighting** for declarations, primitives, user types, enum and union variants, field
  access, namespaces (`std::net`), string interpolation with format specs, `error.Foo`,
  doc comments, modifiers (`owned`, `move`, `borrows`, `async`, `defer`, …) and operators.
- **Language server** (`zark lsp`): diagnostics as you type (also in unsaved buffers),
  completion, hover, signature help, go to definition, references, rename, outline,
  workspace symbols, document highlights, formatting and quick fixes for "did you mean".
- **Snippets** for functions, structs, owned structs, unions, interfaces, async functions,
  lists/maps/arenas, tests, match, closures, imports and more.
- **Commands**:
  - `Zark: Run File` (`Ctrl+Alt+R`) — `zark run <file>` in the "Zark" terminal;
  - `Zark: Test File` (`Ctrl+Alt+T`) — `zark test <file>`;
  - `Zark: Build File` (`Ctrl+Alt+B`) — `zark build <file> -o <file without .zk>`;
  - `Zark: Format Document` (`Ctrl+Alt+F`) — LSP formatting (also on save by default);
  - `Zark: Restart Language Server`;
  - `Zark: Show Output`.
- **CodeLens** above `main` (`Run`), above `test` blocks (`Run tests`) and a `Build` lens
  at the top of a file with a `main`.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `zark.path` | `zark` | Path to the compiler. The default searches the workspace, `PATH` and the usual install directories. |
| `zark.trace.server` | `off` | `messages` or `verbose` traces the LSP traffic into the **Zark** output channel. |

## Development

`extension.js` is plain JavaScript; there is no build step.

```sh
node --check extension.js
python3 pack.py /tmp/zark-lang.vsix
code --install-extension /tmp/zark-lang.vsix --force
```

The grammar is `syntaxes/zark.tmLanguage.json` (scope `source.zk`). It can be checked with
any TextMate-compatible highlighter; the repository's documentation build loads it with
shiki, so `python3 docs-src/build.js` fails on a malformed grammar.

The compiler is native to Linux and macOS; on Windows run VS Code with the WSL remote and
open the project inside WSL. `extensionKind` is `workspace`, so the extension runs next to
the compiler.
