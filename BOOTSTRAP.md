# Bootstrapping Vibe

**Status: Vibe is self-hosted.** The compiler in `selfhost/` (about 4.5k lines of Vibe) compiles itself and reaches a fixed point.

```
./bootstrap.sh
== stage0: Zig reference compiler              (src/*.zig)
== stage1: Vibe compiler built by stage0
== stage2: Vibe compiler built by itself
== stage3: and again
== fixed point reached: stage2 == stage3       (IR and binaries byte-identical)
== native backend: compiler built without LLVM, then by itself
== native fixed point reached: native2 == native3
== test suite with the self-hosted compiler    (21/21, including tokens == Zig reference)
```

| Check | Result |
|---|---|
| stage1 IR == stage2 IR == stage3 IR for `selfhost/main.vibe` | identical (58k lines of LLVM IR) |
| `stage2` binary == `stage3` binary | identical sha256 |
| all examples and the C/C++ interop test with stage2 | same output as with the Zig compiler |
| `tokens` from the Vibe lexer vs the Zig lexer, over all sources | identical (53k tokens) |
| self-compile time | about 0.6 s total; the front end alone takes 55 ms (release) |

## Layout

```
selfhost/lexer.vibe     tokens, automatic semicolons
selfhost/ast.vibe       AST: fat nodes with a kind tag
selfhost/parser.vibe    recursive descent, string interpolation
selfhost/gen.vibe       types, generics instantiation, emission helpers, functions
selfhost/gen_stmt.vibe  statements, defer/errdefer, match (incl. unions)
selfhost/gen_expr.vibe  expressions, addresses, operators, coercions, casts
selfhost/gen_call.vibe  calls, inference, methods, function pointers
selfhost/gen_fmt.vibe   print/bprint/sprint/panic/assert/embed and formatting
selfhost/x64.vibe       x86-64 encoder + ELF64 relocatable object writer
selfhost/native.vibe    native backend: IR -> x86-64 (System V ABI, stack slots, phis, aggregates)
selfhost/main.vibe      driver: imports, prelude (embedded), clang, C/C++ linking
src/                    the Zig compiler, kept as stage0 (and as the reference lexer)
```

The prelude `src/std.vibe` is built into the compiler with `embed`, so `build/vibe` is a single binary. The compiler follows the language's own rule: all of its memory comes from one `Arena` passed in explicitly.
