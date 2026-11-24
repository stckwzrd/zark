# Zark roadmap: what to improve and how

Ordered by payoff. Each item says *how*, not just *what*.

## 1. Native backend: generated code quality (debug builds run 3x slower than gcc -O0)
- **SSA without allocas.** Locals whose address is never taken can be kept as SSA values directly in the frontend (mem2reg on the AST: no `&x`, no capture by a method that takes `*Self`). This removes most load/store pairs, and LLVM `--release` gets faster too.
- **Linear-scan register allocation** over the IR the native backend already parses: live ranges are trivial to compute because values are SSA, and there are about 9 free registers (rbx, r12–r15 callee-saved; r8–r11).
- **Peephole optimizations.** Keep track of which value is in rax and skip the reload when the next instruction uses it. Turn `cmp + setcc + test + jcc` into a direct `jcc`. Encode small immediates as imm8.
- Expected gain: 3–5x at run time, with no measurable cost in compile time.

## 2. Drop the textual IR on the native path
Today the frontend prints LLVM IR text and the native backend parses it back, which is about 40% of backend time. Switch to an in-memory IR (a list of structs) that is either printed as `.ll` (LLVM path) or lowered directly (native path). This is also the base for our own optimizer: constant folding, DCE, inlining small functions.

## 3. Own linker and libc-free runtime → zero external tools for pure Zark
- Write a static ELF executable directly (`.text/.data/.bss` + `_start`). Our object writer already has 90% of this; the remaining part is laying out segments and resolving relocations ourselves.
- `rt.zk` on Linux syscalls: `write`, `mmap`, `exit`, `clock_gettime`, `open/read`, plus our own `printf` subset (the format strings are already built at compile time).
- Linking takes about 40 ms today, so this saves those 40 ms and the clang dependency. The system `ld` remains only for `.c/.cpp` interop.

## 4. Release builds
- Emit `noinline` for very large functions or long call chains (the inliner blow-up in the benchmark), or run our own pass pipeline (`opt -passes=...`) instead of `-O2`.
- Once item 1 lands, LLVM receives SSA instead of allocas and spends less time in SROA/mem2reg.

## 5. Parallel and incremental compilation
- Code generation per function is independent: spread the backend over threads (`pthread_create` through `extern`), one ELF section per thread, merged at the end.
- Cache per module: content hash → `.o` in `.zark-cache`; only modules that changed are recompiled.

## 6. Language
Done: closures with explicit captures, `T: Ord` constraints (checked at the call, not inside the generic body), `match` as an expression, `?T` and `orelse`, modules (`import "x.zk" as x`). Labeled `break`/`continue` are done.
- **Closures with an explicit context:** `fn[ctx](x: i64) i64`, lowered to a {fn, ctx} pair, with no hidden allocation (the context lives where the caller says).
- **Interfaces as generic constraints:** `fn sort[T: Ord](s: []T)`, checked when the generic is declared instead of when it is instantiated, which gives clearer errors.
- **More `comptime`:** reflection over struct fields and generated declarations (basic `comptime` expressions and static assertions are done).
- **Modules / namespaces:** `import "net.zk" as net`, then `net.connect(...)`.
- **SIMD types**: done through LLVM (`f32x4`, `i32x8`, ...). Missing: vector instructions in the own backend, comparisons and masks, shuffles.
- **Overflow checks** in safe mode (`add` + `jo` → panic), removed by `--release`.

## 7. Tooling
Done: `zark lsp` (language server), `zark test`, `zark fmt` (token based: it keeps comments and line breaks), compile errors with the source line, a caret and "did you mean" hints.
- `zark fmt`: the parser already exists; add a printer for the AST.
- `zark test`: `test "name" { ... }` blocks collected and run by the driver.
- DWARF line tables from the native backend: done (`break file:line`, `next`, `bt`). `-g` adds variables, structs and arrays (`print x`, `info locals`). Missing: unions, location lists for register variables, and any debug info on the LLVM path.

## 8. Platforms
An aarch64 backend (Raspberry Pi, ARM laptops) and Windows (PE/COFF + Win64 ABI). The lowering structure in `native.zk` stays the same; only the encoder and the ABI change.

## 9. FFI
Done: C headers (`import "x.h"`, `zark cbind`), the C ABI for structs, unions, variadics and arm64, and layer 4, C++ headers (`import "x.hpp"`: classes, methods, overloads, templates and the `std::string`/`std::vector`/`std::unique_ptr` shims through generated C++ shims; SPEC section 8).
Deferred from layer 4:
- **Subclassing C++ classes from Zark** and overriding virtual functions. One way is a generated C++ subclass whose overrides call Zark `fn` pointers with a context pointer.
- **Exceptions as `!T`.** Today a C++ exception aborts with a message. An opt-in error mode (a manifest key or a `cbind` flag) would map it to an error value.
- **Direct calls by mangled name** for C-shaped signatures, with an `extern` that takes a link name, instead of going through a shim.
- **Lambdas and `std::function`** crossing into C++. Only plain `fn` pointers do today.
- **An `instantiate` key in `zark.toml`** to ask for template specializations without a wrapper `.hpp`.
- **Cross targets and macOS CI for C++ headers.** Only the aarch64 Linux bindings of one header are compared in tests, and the `std::` shims are not checked against libc++.
- **A no-copy marker for owned structs,** so that copying a non-trivial C++ object in Zark (`auto x = *p;`) is a compile error.
