---
title: The Vibe Guide
order: 0
description: A complete guide to the Vibe programming language
---

<div class="hero">

# Vibe

A small systems language: you control memory, type conversions are visible in the code, and there are no hidden allocations or hidden control flow. The compiler is written in Vibe itself and builds itself in about a tenth of a second.

</div>

```vibe run
void main() {
    const auto name = "world";
    println("Hello, {name}! 6 * 7 = {6 * 7}");
}
```

This is the complete guide. Every example on these pages was compiled and run by the real compiler when the site was built, and the text under an example is what the program actually printed. If an example is supposed to fail to compile, the real compiler message is shown under it.

## Where to start

<div class="cards">
<a href="getting-started.html"><b>Installation and the first program</b><span>Build the compiler, run Hello World, learn the commands and flags.</span></a>
<a href="showcase.html"><b>Showcase</b><span>A multithreaded ray tracer: interfaces, SIMD, JSON, threads, unions and tests in one program.</span></a>
<a href="tour.html"><b>Quick tour</b><span>The whole language on one page: about twenty small programs.</span></a>
<a href="types.html"><b>Types</b><span>Numbers, pointers, slices, strings, arrays and the conversion rules.</span></a>
<a href="errors-and-optionals.html"><b>Errors</b><span><code>!T</code>, <code>?</code>, <code>catch</code>, <code>errdefer</code> and optional values.</span></a>
<a href="memory.html"><b>Memory</b><span>Allocators, arenas, ownership and how not to leak.</span></a>
<a href="cookbook.html"><b>Cookbook</b><span>More than thirty complete programs, from FizzBuzz to a calculator.</span></a>
</div>

## How the guide is organized

- **Start**: installation and an overview of the language. You can read it in an evening.
- **Language**: every feature on its own, with all the details and error messages.
- **Memory and data**: allocators, slices, `List` and `Map`.
- **Interop and tools**: calling C, tests, formatting, the language server.
- **Reference**: the standard library, recipes, pitfalls, how the compiler works and a cheat sheet.

The search box opens with the `/` key. You can read the pages in any order; the links between them lead to where a rule is explained in more detail.

> **Tip:** if you come from C, Go, Rust or Zig, start with the [quick tour](tour.md), then open [pitfalls and FAQ](gotchas.md): it collects the differences and has a comparison table.

## Principles of the language

1. **No hidden allocations.** No language construct and no prelude function takes memory by itself. Memory comes only from an `Allocator` that you pass explicitly.
2. **No hidden control flow.** The only implicit things are `defer`/`errdefer` (written next to the code they affect), bounds checks (which can be turned off) and `==` on strings.
3. **One way to do one thing.** `auto`/`const` for bindings, `?` to propagate errors, `catch` to handle them, `match` for branching.
4. **Conversions are visible.** Only safe integer widening, `T` → `!T`, `T` → `?T`, `null` → pointer and `*T` ↔ `*void` are implicit. Everything else goes through `as`.
5. **What you see is what is in memory.** Structs are laid out as in C, and `str` is `{pointer, length}`.
