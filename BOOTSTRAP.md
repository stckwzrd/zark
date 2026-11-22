# Bootstrapping Zark

**Status: Zark is self-hosted.** The compiler in `selfhost/` (about 4.5k lines of Zark) compiles itself and reaches a fixed point.

```
./bootstrap.sh
== seed: bootstrap/seed.ll.gz -> clang
== stage1: Zark compiler built from the seed
== stage2: Zark compiler built by itself
== stage3: and again
== fixed point reached: stage2 == stage3       (IR and binaries byte-identical)
== native backend: compiler built without LLVM, then by itself
== native fixed point reached: native2 == native3
== test suite with the self-hosted compiler    (21/21, including golden tokens)
```

| Check | Result |
|---|---|
| stage1 IR == stage2 IR == stage3 IR for `selfhost/main.zk` | identical (58k lines of LLVM IR) |
| `stage2` binary == `stage3` binary | identical sha256 |
| all examples and the C/C++ interop test with stage2 | output matches `tests/expected` |
| `tokens` of the examples and error tests | match the golden files in `tests/tokens` |
| self-compile time | about 0.6 s total; the front end alone takes 55 ms (release) |

## Layout

```
selfhost/lexer.zk     tokens, automatic semicolons
selfhost/ast.zk       AST: fat nodes with a kind tag
selfhost/parser.zk    recursive descent, string interpolation
selfhost/gen.zk       types, generics instantiation, emission helpers, functions
selfhost/gen_stmt.zk  statements, defer/errdefer, match (incl. unions)
selfhost/gen_expr.zk  expressions, addresses, operators, coercions, casts
selfhost/gen_call.zk  calls, inference, methods, function pointers
selfhost/gen_fmt.zk   print/bprint/sprint/panic/assert/embed and formatting
selfhost/x64.zk       x86-64 encoder + ELF64 relocatable object writer
selfhost/native.zk    native backend: IR -> x86-64 (System V ABI, stack slots, phis, aggregates)
selfhost/main.zk      driver: imports, prelude (embedded), clang, C/C++ linking
bootstrap/seed.ll.gz    the compiler's own LLVM IR, the starting point of the bootstrap
tools/update-seed.sh    regenerates the seed after a fixed-point check
legacy/zig-stage0/      the retired Zig compiler (history only)
```

The prelude `std/std.zk` is built into the compiler with `embed`, so `build/zark` is a single binary. The compiler follows the language's own rule: all of its memory comes from one `Arena` passed in explicitly.
