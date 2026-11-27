---
title: The safety model
order: 20.5
section: Memory and data
description: Exactly what Zark checks at compile time, what it checks while running, what it leaves to you, and how to cover the rest with tools
---

Zark is a systems language, so it cannot promise what a garbage-collected language promises. It makes a narrower, honest promise: **a mistake is stopped as early as the compiler can see it, and otherwise it is stopped loudly, with a file and a line, instead of corrupting memory in silence.** This page lists every case, so you know what you can lean on.

## Build modes

| Mode | How | Checks | Use it for |
|---|---|---|---|
| safe | `zark run`, `zark build` | everything below | development, tests, most programs |
| safe and optimized | `-O` | the same checks, optimized by LLVM | production when you want the checks to stay |
| unchecked | `--release` | bounds, division, overflow and null checks removed | a program that you have already run through the safe modes |
| bare metal | `--freestanding` | no runtime helpers, so no checks | kernels and drivers |

Compile-time checks (types, ownership, escapes) are the same in all modes. The difference is only what is checked while the program runs.

## The three outcomes

Every problem ends in exactly one of three ways.

1. **A compile error.** The program is not built. This is the best outcome.
2. **A panic.** The program stops at once with a message, a file and a line (`panic: index 3 out of bounds (len 3) at main.zk:4`). A panic means a bug in the program, and it cannot be caught.
3. **An error value.** A function returns `!T` and the caller decides. This is for things that can go wrong in a correct program: no file, bad input, no memory.

## What is stopped, and when

| Mistake | What happens |
|---|---|
| Wrong type, lossy conversion, missing `as` | compile error |
| Number literal outside its type (`u8 x = 300`) | compile error |
| Assigning to a `const` | compile error |
| Dropping an `!T` result | compile error |
| A `match` that produces a value and misses a variant | compile error |
| A forgotten variant in a `match` statement | nothing happens (statements may skip variants) |
| A struct that contains itself, an alias cycle, an infinitely growing generic | compile error |
| Using a variable after `free`, `destroy`, `deinit`, `close` or `join` | compile error |
| Freeing the same variable twice | compile error |
| Returning or storing a pointer or slice into a local | compile error |
| Using a pointer or slice into a `List` or `Map` after it changed | compile error |
| Changing a `List` or `Map` inside a loop that iterates over it (and goes on to the next round) | compile error |
| Copying a resource element by a runtime index (`l[i]`, `List.get(i)`) | compile error |
| Moving or mutating an element out of a `for` over a container of resources | compile error |
| Matching a resource union and using the matched value afterwards | compile error |
| Unwrapping a resource optional or error union and using the value afterwards | compile error |
| A `Thread` that is not joined on every path, dropped, or returned together with a local it captured | compile error |
| `comptime` assertion that is false | compile error |
| Index or slice out of bounds | panic |
| Integer division or remainder by zero, or `MIN / -1` | panic |
| Integer overflow in `+`, `-`, `*` | panic |
| Out of memory, bad input, a missing file | error value |
| A `List` that was never given an allocator | error value (`error.NoAllocator`) |
| A float that does not fit an integer (`1e30 as i32`) | saturates to the nearest limit, `nan` becomes 0 |
| A shift by too many bits | the count is masked to the width of the type |
| Reading a variable that was never assigned | not possible: variables start as zero |
| Dereferencing `null`, or running out of stack by endless recursion | the program stops with a clear message and a backtrace |

Nothing in the list is undefined behavior in the safe mode. The same program gives the same result with the native backend, with `--llvm` and with `-O`, and a test in the repository keeps it that way.

**A check that cannot fire is not emitted.** The compiler keeps a small range analysis while it generates a function: `if (n < 2) { return; }` proves `n >= 2` for the rest of the block, `if (n > 100) { return; }` proves `n <= 100`, and `for i in lo..hi` proves `lo <= i < hi`. So `n - 1`, `i - 1` and `n + 1` go out without an overflow check exactly when the operation cannot overflow, and with the check everywhere else. A proof dies the moment the value can change: on an assignment, on `&n`, when a closure captures it, and when the name is declared again in a nested scope. Narrow types keep their checks, because a proof about `i64` says nothing about an `i32` that wraps earlier. `tests/std/range_facts.zk` covers the values and `tests/panics/range_fact_*.zk` keep the panic where it still belongs.

## Ownership and borrowing without a borrow checker

Zark does not have lifetimes or a borrow checker as Rust has. It has something smaller that you can learn in ten minutes, and that catches the mistakes that happen in practice. It follows **variables** inside **one function**:

- A parameter or method marked `move` takes the value over. The standard library marks `free`, `destroy`, every `deinit`, `join`, and the `close` of sockets and streams. After the call, the variable is dead until you assign it again.
- A method marked `borrows` returns a pointer or slice into the object (`List.at`, `List.slice`, `Map.get_ptr`). A method marked `invalidates` may move the memory (`push`, `put`, `insert`). If you call an `invalidates` method, every pointer or slice you took from that object earlier is dead.
- A pointer or slice to a local array or struct cannot leave the function: not by `return` and not by being stored through a pointer parameter or into a global.
- A loop that iterates over a container (`for (auto x : list)`, `list.slice()`, `this->items`) cannot call an `invalidates` method on it and then go on to the next round. Leave with `break` or `return` right after the change, or iterate over a copy. A non-resource element is copied by value; a resource element is a non-owning copy (below).
- A resource element read by a runtime index (`l[i]`, `List.get(i)`) is rejected: the checker follows names and constant paths, so a runtime index cannot be tracked and the copy would alias the container. A constant index rooted in a local moves that path. Inside the container's own methods (`this->items[i]` in `pop`, `remove_at`, ...) the read is trusted, because only the container knows whether the slot is still live.
- A resource reached through a pointer or a slice (`this->l`, `hp->l`, `s[0]`, `(*p).l`) cannot be copied or moved out: `auto y = this->l`, `return this->l`, `f(this->l)` and `take(this->l)` are compile errors, because the copy would alias storage the pointer or container still owns. A field or constant index of a local value (`h.l`, `l.items[0]`) moves normally. `Map.get` and `Map.get_or` are rejected for a resource value, like `List.get`; borrow with `get_ptr(key)`.
- A `for` over a container of resources gives a non-owning copy of each element: read it and call its `borrows` methods, but do not move it out (a `move` parameter, `deinit`, a resource field) and do not call an `invalidates` method on it or on a field (`x.inner.push`), because the copy's header would change while the container still points at the old buffer. Take an element out with `pop`/`remove_at`/`swap_remove`, or use `move_out(&c[i])`. A closure cannot capture it either, because the capture is a pointer to the copy.
- `match (u)` on a resource union takes `u` over: the arm binding owns the payload and using `u` afterwards is a compile error. Inside a `for` over resources the binding is a non-owning view with the same rules as the loop variable.
- `x orelse d` and `x catch d` copy the payload out, so a resource optional or error union in a place is consumed by the unwrap; using `x` afterwards is a compile error.
- A struct declared `owned` (in the standard library, `Thread`) must be consumed in every scope it lives in: joined, detached, passed on, or returned. This includes the exits taken by `?`, so write `defer t.join();` or `errdefer t.join();` right after creating it. Dropping such a value on the spot is refused.

The state is followed through `if`, `match`, `catch`, loops, `defer` and `errdefer`. The checker is deliberately conservative where it would otherwise reject valid programs, so it says nothing about what it cannot see. Four things it does not see:

- **Copies.** `auto q = p; a.destroy(p); use(q)` is not caught.
- **Fields for `move`.** `a.free(this->data)` does not mark the field as freed. (Borrows and `invalidates` do follow field paths such as `this->items`.)
- **Other functions.** A function that frees what you passed to it, without being marked `move`, is invisible.
- **Data races.** Nothing checks that two threads do not touch the same memory.

You can mark your own functions with the same words, and the check then covers them too. See [memory](memory.md#use-after-free-is-a-compile-error).

## Closing the gap with tools

What the compiler cannot prove, a tool can catch while you test.

**`DebugAllocator`** gives every block its own pages and makes a freed block inaccessible. A use after free, even through a copy of the pointer, stops at the exact access with the block's number, and `deinit()` lists everything that was never freed.

```zark run exit
void touch(i64* p) { *p = 1; }

!void main() {
    auto dbg = DebugAllocator::init();
    const auto a = dbg.allocator();
    auto p = a.create<i64>()?;
    const auto copy = p;
    a.destroy(p);
    touch(copy);
}
```

```zark run exit
!void main() {
    auto dbg = DebugAllocator::init();
    const auto a = dbg.allocator();
    _ = a.create<i64>()?;
    _ = a.alloc<u8>(100)?;
    dbg.deinit()?;
}
```

Run your tests with a `DebugAllocator` as the allocator. Because functions receive the allocator as a parameter, no code needs to change to do it.

**`zark test`** runs every `test` block. **`-g`** adds line and variable information for `gdb`. **A crash handler** prints the signal, the reason (null pointer, stack overflow, use after free) and a backtrace, and `ZARK_CRASH_HANDLER=0` turns it off to get a core file. See [tooling](tooling.md).

## Threads

Closures capture variables by pointer. A thread that outlives the variables it uses reads freed stack. The rules:

1. Join every thread before the variables its closure uses go out of scope.
2. Protect shared data with a `Mutex`, or use `AtomicI64`, or pass values through a `Channel`.
3. Do not copy a `Mutex`, `Cond`, `WaitGroup` or `Channel` once it is in use. Share it by pointer.

The compiler enforces the first rule for a `Thread` held in a variable: it must be joined on every path, including the failing ones (see [threads](net-threads.md)). It does not see threads kept in a list or array, data races, or the order of joins. Write the `join` next to the `spawn`, the way you write `defer` next to an allocation, and test with several threads.

## A checklist before you ship

- [ ] All tests pass in the safe mode, with a `DebugAllocator` in the memory tests.
- [ ] `zark build -O` passes the same tests.
- [ ] Every `+%`, `-%` and `*%` in the code is there for a reason (a hash, a counter).
- [ ] Every `comptime assert` that guards a file format or a layout is still there.
- [ ] Only then, if you need the speed, build with `--release` and run the tests again.

## What next

- The error messages in detail: [debugging](debugging.md).
- How to write code the checks like: [idioms](idioms.md).
