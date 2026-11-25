---
title: "Tools: fmt, lsp, flags"
order: 32
section: Interop and tools
description: The formatter, the language server, compilation modes, diagnostics and debugging in Zark
---

All the tools are subcommands of one executable, `zark`. Nothing separate needs to be installed.

## Compiler diagnostics

Every error is printed in the form `file:line: error: message`, and under it the source line is shown with a `^` pointing at the place of the error:

```zark error
void main() {
    const auto count = 1;
    println("{cuont}");
}
```

When the program has a similar name, the compiler suggests it (for names shorter than three characters no suggestions are shown, they would be random):

- an unknown variable or function;
- a struct field, an enum or union variant, a name in a closure's capture list;
- the name of a generic constraint (`T: Orb` → `Ord`).

Typical messages and their causes are explained on the page [pitfalls and FAQ](gotchas.md).

> **Note:** the compiler stops at the **first** parser error. It also reports type errors one per run, but the [language server](#language-server-and-editor) checks every function separately and shows one error per function.

## zark fmt

`zark fmt file.zk ...` rewrites files in place. The formatter works on tokens: it fixes spaces, indentation and blank lines, **never wraps or joins lines** and does not touch comments.

```sh
$ cat ugly.zk
//   header comment


import "x.zk";   // trailing


struct P{i64 x;i64 y;}
i64   add( i64 a ,i64 b )  {
return a+b;   // sum
}
void main()  {
auto   p=P{.x=1,.y=2};
	if (p.x==1&&p.y>0){
println("ok {p.x}");
 }else{
    println("no");
}
for (auto i : 0..10){total+=i*2-1;}
match total {
1,2=>println("a"),
_ => { println( "b" ); }
}
const auto r=-q+ (add(q,1)*2);
i64* z=&p;
}

$ zark fmt ugly.zk
formatted ugly.zk
$ cat ugly.zk
//   header comment

import "x.zk";   // trailing

struct P { i64 x; i64 y; }
i64 add(i64 a, i64 b) {
    return a + b;   // sum
}
void main() {
    auto p = P{ .x = 1, .y = 2 };
    if (p.x == 1 && p.y > 0) {
        println("ok {p.x}");
    } else {
        println("no");
    }
    for (auto i : 0..10) { total += i*2 - 1; }
    match total {
        1, 2 => println("a"),
        _ => { println("b"); }
    }
    const auto r = -q + (add(q, 1)*2);
    i64* z = &p;
}
```

What exactly the formatter does:

- indentation is 4 spaces per level of bracket nesting; a continuation of an expression on the next line gets one more level;
- spaces around binary operators, after commas and colons, inside `{ }` on one line; no spaces inside `()` and `[]`; the angle brackets of generics (`List<i64>`) stay as written;
- runs of blank lines collapse into one, and blank lines right after `{` and before `}` are removed;
- trailing spaces are removed, and the file ends with exactly one newline;
- the distance between code and a trailing comment is kept as it is.

What the formatter does **not** do: it does not break long lines, does not align comments to a column, does not reorder declarations, does not rename anything. Spaces around `*` and `&`, when the neighboring tokens do not show whether it is multiplication or a pointer (`i*2` in the example above), are left as they were.

`--check` changes nothing and prints `would reformat file` for every file that would be changed, and exits with code 1: handy for CI:

```sh
$ zark fmt --check ugly.zk
would reformat ugly.zk
$ echo $?
1
```

The formatter is idempotent: running it again on an already formatted file changes nothing. It is guaranteed to preserve the stream of tokens: the meaning of the program cannot change.

> **Note:** files with `\r\n` line endings are turned into `\n` by the formatter.

## Compilation modes

Zark has two backends:

- **the own x86-64 backend** (the default). The compiler itself turns the intermediate representation into machine code and writes an ELF object. The build is very fast; the code is noticeably faster than "naive" code because there is register allocation, but slower than optimized LLVM;
- **LLVM** (`--llvm`, `-O`, `--release`): the compiler prints LLVM IR, and `clang` optimizes and compiles it.

| Command | Backend | Optimization | Bounds checks |
|---|---|---|---|
| `zark run x.zk` | own | none | yes |
| `zark run x.zk --llvm` | LLVM | `-O0` | yes |
| `zark run x.zk -O` | LLVM | `-O2` | yes |
| `zark run x.zk --release` | LLVM | `-O2` | **no** |
| `zark run x.zk --no-safety` | own | none | **no** |

The bounds check is what turns going out of an array into a clear panic. Without it this is **undefined behavior**: the example below fails with a `panic` in a normal build and silently reads garbage with `--release`:

```sh
$ zark run oob.zk
panic: index 5 out of bounds (len 3) at oob.zk:4
$ zark run oob.zk --release
140735146892504
```

(`oob.zk` reads `a[5]` of an array of three elements.) Keep debug builds with the checks, and turn on `--release` for finished programs when you are sure the indexes are correct.

For development use the default mode: it builds the compiler itself (about 25 thousand lines of Zark) in about a third of a second, not counting the link.

## Intermediate representations

`zark ir file.zk` prints the LLVM IR that the frontend generated. It is the same text that the own backend reads. For the function

```zark
i64 fib(i64 n) {
    if (n < 2) { return n; }
    return fib(n - 1) + fib(n - 2);
}
```

you get (local variables live in `alloca`, the names `%tN` are temporary values):

```text
define internal i64 @vb.fib(i64 %a.0) {
entry:
  %v.n.1 = alloca i64
  store i64 %a.0, ptr %v.n.1
  %t2 = load i64, ptr %v.n.1
  %t3 = icmp slt i64 %t2, 2
  br i1 %t3, label %then1, label %endif3
then1:
  %t4 = load i64, ptr %v.n.1
  ret i64 %t4
endif3:
  %t5 = load i64, ptr %v.n.1
  %t6 = sub i64 %t5, 1
  %t7 = call i64 @vb.fib(i64 %t6)
  %t8 = load i64, ptr %v.n.1
  %t9 = sub i64 %t8, 2
  %t10 = call i64 @vb.fib(i64 %t9)
  %t11 = add i64 %t7, %t10
  ret i64 %t11
}
```

`zark tokens file.zk` prints the tokens: the line number, the kind of the token and the text. Useful when it is unclear how the lexer split a line (especially with quotes and curly braces):

```text
1 .ident i64
1 .ident fib
1 .lparen (
1 .ident i64
1 .ident n
1 .rparen )
```

How everything else works is on the page [how the compiler works](how-it-works.md).

## Language server and editor

`zark lsp` is a language server over the LSP protocol on standard input/output. It is built on the same parser and generator as the compiler, so the messages are the same as with `zark build`, and they also apply to unsaved changes. Features:

| Feature | What it can do |
|---|---|
| Diagnostics | errors with an exact range as you type, "did you mean" hints, quick fixes |
| Hover | the signature of a symbol and the `///` comments above the declaration |
| Completion | struct members and methods (by the inferred type) after `.`, `->` and `::`, module names after `alias::`, enum variants after `.`, literal fields after `.` inside `Name{ ... }`, local variables, global names, keywords |
| Parameter hints | when typing `(` and `,`: the signature of the function or method being called |
| Go to definition | including into imported files and by the path inside `import "..."` |
| References and rename | across the whole working directory, including the files that import your file |
| File outline | a tree of structs, enums, functions, methods and tests |
| Symbol search | `Ctrl+T` over all the `.zk` files of the working directory |
| Occurrence highlighting | all the uses of the symbol under the cursor |
| Formatting | the same as `zark fmt` |

> **Note:** diagnostics work like this: the server runs the compiler's frontend on every function of the file (except generic ones, which are checked only when they are called) and collects one error per function. The parser stops at the first syntax error in a file.

What the server does **not** do: it does not show the types of expressions, cannot refactor except for renaming, and does not infer types in complex generic expressions (there are simply no hints there).

### VS Code and code-oss

The repository contains the extension `editors/vscode`. It starts `zark lsp` and adds syntax highlighting, snippets, run and test buttons, and the command "Zark: Restart Language Server".

```sh
cd editors/vscode
npm install
python3 pack.py zark-lang.vsix
code-oss --install-extension zark-lang.vsix      # or: code --install-extension zark-lang.vsix
```

After installing, reload the window (`Ctrl+Shift+P` → "Developer: Reload Window") and open any `.zk` file. Settings:

| Setting | Value |
|---|---|
| `zark.path` | the path to `zark`; by default it is searched in `PATH`, then in `~/.local/bin` |
| `zark.trace.server` | `off`, `messages` or `verbose`: a log of the exchange with the server in the output tab |

Hotkeys: `Ctrl+Alt+R` runs the file, `Ctrl+Alt+T` runs the tests. "Run" links appear above `main` and above every `test`. Formatting on save is on by default for `.zk`.

### Other editors

Any LSP client will do: the start command is `zark lsp`, the transport is stdio, the file extension is `.zk`. Below are typical settings; I have not checked them in every editor, so treat them as a starting point.

```text
-- Neovim (0.11+)
vim.filetype.add({ extension = { zark = "zark" } })
vim.lsp.config("zark", { cmd = { "zark", "lsp" }, filetypes = { "zark" }, root_markers = { ".git" } })
vim.lsp.enable("zark")
```

```text
# Helix: languages.toml
[language-server.zk]
command = "zark"
args = ["lsp"]

[[language]]
name = "zark"
scope = "source.zk"
file-types = ["zark"]
language-servers = ["zark"]
comment-token = "//"
indent = { tab-width = 4, unit = "    " }
```

```text
;; Emacs (eglot)
(add-to-list 'auto-mode-alist '("\\.zk\\'" . prog-mode))
(add-to-list 'eglot-server-programs '(prog-mode . ("zark" "lsp")))
```

Highlighting for Zed, Sublime and other editors can use the TextMate grammar from `editors/vscode/syntaxes/zark.tmLanguage.json`.

## Debugging

- **`println`** is the main tool. Output goes out at once, and `eprintln` writes to stderr.
- **`panic("message {x}")`** prints the message with a file and line and ends the program with code 1.
- **`assert(condition)`** panics with a file and line if the condition is false.
- **`zark ir`** lets you see how the compiler understood the program and find, for example, extra copies of aggregates.
- **gdb**: the own backend puts a DWARF line table into the file. `break file.zk:12`, `next`, `step` and `bt` with line numbers work; in a backtrace the functions look like `vb[fib]`, `vb[main]`. Add `-g` to also see variables: `zark build x.zk -g` keeps every local in a stack slot and describes it, so `print x`, `info locals` and `up` work (integers, floats, `bool`, pointers, structs, arrays and strings; unions and interfaces are not described yet). Without `-g` the variables may live in registers and are not described. Builds through `--llvm` and `--release` contain nothing but function symbols.
- **`zark tokens`** helps when you suspect a lexer problem: an unclosed quote, a curly brace inside a string and the like.

## Cache and temporary files

All the build debris lives in `.zark-cache/` in the current directory: object files, `.ll` (for the LLVM mode), objects of external C/C++ files and the executable of `zark run`. The directory is safe to delete entirely. Tests (`zark test`) create `name.test` and `test.out` there.

## Environment variables and version

The compiler has no environment variables for configuration. It calls `clang` (and `clang++` if there is C++ among the extra files) from `PATH`.
