---
title: Memory and allocators
order: 20
section: Memory and data
description: The stack and the heap, the explicit Allocator, c_allocator, FixedBuf, Arena, create/destroy, your own allocator and the typical memory mistakes in Vibe
---

The main rule of the language: **nothing allocates memory by itself.** Not strings, not interpolation, not closures, not `println`. The heap appears only where you explicitly passed an **allocator**. So when you read code you always see who takes how much and where.

## The stack and the heap

Ordinary variables, arrays and structs live on the **stack** of a function and disappear when it exits. For data that must outlive that, or whose size is not known in advance, you need the **heap**, and it is reached through an allocator.

```vibe run
void main() {
    i64[4] local;
    local[0] = 1;
    println(local, sizeof(u8[256]));
}
```

A fixed-size array on the stack is the cheapest way to get memory. But the size must be known at compile time, and you cannot return such an array as a slice from a function: the stack is freed after the return.

## Allocator

`Allocator` is a small struct of three fields: a context and two functions.

```vibe
struct Allocator {
    void* ctx;
    fn(void*, u64, u64) -> void* alloc_fn;
    fn(void*, void*, u64) free_fn;
}
```

Any allocator is such a triple of values. The ready-made allocators of the standard library:

| Allocator | Where the memory comes from | Freeing |
|---|---|---|
| `c_allocator()` | `calloc` / `free` from libc | each piece separately |
| `FixedBuf::init(buf)` | your ready buffer, no heap | `reset()` for everything at once |
| `Arena::init(parent)` | in chunks from a parent allocator | `deinit()` for everything at once |

And the methods of any allocator `a`:

| Method | What it does |
|---|---|
| `!T[] a.alloc<T>(n)` | `n` elements filled with **zeros** |
| `a.free(slice)` | frees a slice obtained from `alloc` |
| `!T* a.create<T>()` | one `T` on the heap, zeroed |
| `a.destroy(p)` | frees a `create` |
| `!str a.dup(s)` | a copy of a string |
| `!u8* a.dupz(s)` | a copy with a zero byte at the end, for C |

Every allocation operation returns `!...`: when memory runs out, you get an ordinary `error.OutOfMemory`, not a crash.

### `alloc` and `free`

```vibe run
!void main() {
    const auto a = c_allocator();
    const auto xs = a.alloc<i64>(4)?;
    defer a.free(xs);
    println(xs, xs.len);
    xs[0] = 10;
    xs[3] = 40;
    println(xs);
}
```

The memory is zeroed, so you can read it without initializing it. The size of the slice is `xs.len`.

> **Tip:** write `defer a.free(...)` right after obtaining memory. Then it is released on any exit from the function, even on an error.

### `create` and `destroy`

For a single object, such as a list node:

```vibe run
struct Node {
    i64 val;
    Node* next;
}

!void main() {
    const auto a = c_allocator();
    const auto n1 = a.create<Node>()?;
    defer a.destroy(n1);
    const auto n2 = a.create<Node>()?;
    defer a.destroy(n2);
    n1.val = 1;
    n1.next = n2;
    n2.val = 2;
    println(n1.val, n1.next.val, n2.next == null);
}
```

### `dup`

```vibe run
!void main() {
    const auto a = c_allocator();
    u8[3] src = [104, 105, 33];
    const auto copy = a.dup(src[..])?;
    defer a.free(copy);
    src[0] = 72;
    println(copy, src[..]);
}
```

## The out-of-memory error

In Vibe, running out of memory is not a catastrophe but a value that gets handled. This matters most for `FixedBuf`, whose memory is limited:

```vibe run
void main() {
    u8[64] mem;
    auto fb = FixedBuf::init(mem[..]);
    const auto a = fb.allocator();
    println(fb.remaining());
    const auto first = a.alloc<u8>(40) catch return;
    println(first.len, fb.remaining());
    const auto second = a.alloc<u8>(40) catch |e| {
        println("not enough: {e}");
        return;
    };
    println(second.len);
}
```

## `FixedBuf`: no heap at all

`FixedBuf` hands out memory from your array in ascending order. Individual pieces need not be freed: `free` returns memory only if it was the very last allocation, otherwise it does nothing. The whole buffer is returned with one call to `reset()`. The allocator keeps a pointer to `fb`, so the variable `fb` must live as long as you use the allocator.

```vibe run
!void main() {
    u8[256] mem;
    auto fb = FixedBuf::init(mem[..]);
    const auto a = fb.allocator();

    auto list = List<i64>::init(a);
    for (auto i : 0..5) { list.push(i * i)?; }
    println(list.slice(), fb.remaining());

    fb.reset();
    println(fb.remaining());
}
```

Uses: embedded systems, handling a request "within a budget", functions that must not touch the heap. All code on `FixedBuf` works without a single `malloc`.

> **Gotcha:** after `fb.reset()` all pieces handed out earlier are invalid (nothing protects them). Do not use old slices and containers after a reset: the `list` above would have to be initialized again.

## `Arena`: allocate a lot, free at once

`Arena` takes large chunks from a parent allocator and hands small pieces out of them. The chunks are taken in portions of 64 KB. Individual `free`s do nothing, and `deinit()` frees **everything** at once. It is ideal for data with a common lifetime: parsing a file, handling one request, building a tree.

```vibe run
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    auto words = List<str>::init(a);
    const auto w1 = a.dup("alpha")?;
    const auto w2 = a.dup("beta")?;
    words.push(w1)?;
    words.push(w2)?;
    println(words.slice());

    for (auto i : 0..1000) {
        _ = a.alloc<i64>(100)?;
    }
    println("a thousand arrays allocated and not a single free");
}
```

There is no need to call `list.deinit()` or `a.free(w1)`: everything goes away with `arena.deinit()`. This is exactly how the Vibe compiler itself works: one arena per run.

A typical pattern: the allocator is passed as a parameter.

```vibe run
struct Config {
    str name;
    List<i64> values;
}

!Config load(Allocator a) {
    auto cfg = Config{ .name = a.dup("config")?, .values = List<i64>::init(a) };
    for (auto i : 1..4) { cfg.values.push(i * 10)?; }
    return cfg;
}

!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto cfg = load(arena.allocator())?;
    println(cfg.name, cfg.values.slice());
}
```

The function `load` does not know which allocator it was given. The caller decides: an arena, a `FixedBuf` or `c_allocator`.

## Your own allocator

It is enough to fill in three fields. For example, a counter that counts allocations and hands the work to a parent:

```vibe run
struct Counting {
    i64 count;
    i64 bytes;
    Allocator parent;
}

void* count_alloc(void* ctx, u64 size, u64 align) {
    const auto c = ctx as *Counting;
    c.count += 1;
    c.bytes += size as i64;
    return c.parent.alloc_fn(c.parent.ctx, size, align);
}

void count_free(void* ctx, void* p, u64 size) {
    const auto c = ctx as *Counting;
    c.parent.free_fn(c.parent.ctx, p, size);
}

!void main() {
    auto stats = Counting{ .count = 0, .bytes = 0, .parent = c_allocator() };
    const auto a = Allocator{ .ctx = &stats as *void, .alloc_fn = count_alloc, .free_fn = count_free };

    auto list = List<i64>::init(a);
    defer list.deinit();
    for (auto i : 0..20) { list.push(i)?; }
    println(list.len, stats.count, stats.bytes);
}
```

`alloc_fn(ctx, size, align)` must return **zeroed** memory, or `null` when there is not enough. `free_fn(ctx, ptr, size)` receives the pointer and the same size.

20 elements took three allocations (8, 16 and 32 elements of 8 bytes: 64 + 128 + 256 = 448 bytes): the list doubles its capacity.

## Stack data and pointers

A pointer to a local variable must not be returned:

```vibe error
i64* bad() {
    auto x = 5;
    return &x;
}

void main() { println(*bad()); }
```

After `bad` exits the stack is overwritten and the pointer would "dangle", so the compiler refuses the code. The same goes for a slice of a local array and for a thread whose closure captured a local (see [pointers that outlive their memory](#pointers-that-outlive-their-memory)). A closure that you return by hand is still your responsibility (see [closures](functions.md#closures)).

The rule: data that outlives a function must live in memory owned by the caller (a slice parameter, a pointer, an allocator).

```vibe run
void fill(i64[] out) {
    for (auto i : 0..out.len) { out[i] = i * i; }
}

void main() {
    i64[5] buf;
    fill(buf[..]);
    println(buf);
}
```

## Use after free is a compile error

A parameter can be marked `move`: the function takes the value over, and the caller must not use that variable again. The standard library marks `free`, `destroy` and every `deinit`/`close`, so the most common memory bugs stop at compile time.

```vibe error
void main() {
    const auto a = c_allocator();
    auto p = a.create<i64>() catch return;
    *p = 7;
    a.destroy(p);
    println(*p);
}
```

The same applies to a double `free`, including the one hidden behind a `defer`, and to using a `List` after `deinit()`:

```vibe error
void main() {
    const auto a = c_allocator();
    auto buf = a.alloc<u8>(16) catch return;
    defer a.free(buf);
    a.free(buf);
}
```

Assigning a new value brings the variable back to life. Branches are followed: a variable consumed on one path of an `if` cannot be used afterwards, and a variable consumed inside a loop must be reassigned or left with `break`/`return`.

```vibe run
void main() {
    const auto a = c_allocator();
    auto buf = a.alloc<u8>(16) catch return;
    a.free(buf);
    buf = a.alloc<u8>(32) catch return;
    println(buf.len);
    a.free(buf);
}
```

You can use `move` in your own code. On a parameter it goes before the type; on a method, after the parameter list:

```vibe run
struct Conn {
    i64 fd;
    void close() move { println("closed {this->fd}"); }
}

void finish(move Conn* c) { c->close(); }

void main() {
    auto c = Conn{ .fd = 7 };
    finish(&c);
}
```

The check follows names, not memory. It sees `a.free(buf)` followed by `buf`, but it does not see `auto copy = buf; a.free(buf); use(copy)`, and it does not track fields (`this->items`). For those cases use the `DebugAllocator`, which stops the program at the exact access.

## Pointers that outlive their memory

The compiler follows where a pointer or a slice comes from. A pointer into a local variable cannot leave the function, neither through `return` nor by being stored in a parameter:

```vibe error
i64* first_of() {
    i64[4] a;
    auto p = &a[1];
    return p;
}

void main() { println(*first_of()); }
```

```vibe error
struct Slot { i64* p; }

void put(Slot* out) {
    i64 x = 1;
    out->p = &x;
}

void main() {
    Slot s;
    put(&s);
}
```

A pointer or slice into a container is valid until the container changes. The methods that can move the memory (`push`, `append`, `insert`, `reserve`, `Map.put`, `remove`) are marked `invalidates`, and the methods that hand out a pointer into it (`at`, `slice`, `get_ptr`) are marked `borrows`. Using such a pointer after an invalidating call is an error, and so is using a slice after `free` of the buffer it came from:

```vibe error
void main() {
    auto l = List<i64>::init(c_allocator());
    defer l.deinit();
    l.push(1) catch return;
    auto p = l.at(0);
    l.push(2) catch return;
    println(*p);
}
```

Take the pointer again after the change and everything is fine:

```vibe run
void main() {
    auto l = List<i64>::init(c_allocator());
    defer l.deinit();
    l.push(1) catch return;
    auto p = l.at(0);
    *p = 10;
    l.push(2) catch return;
    p = l.at(1);
    *p = 20;
    println(l.get(0), l.get(1));
}
```

Changing a container while a loop walks over it is the same mistake in another costume: the loop keeps reading the old buffer. The compiler follows `for` loops too, and `this->items` counts as much as a local variable:

```vibe error
void main() {
    auto l = List<i64>::init(c_allocator());
    defer l.deinit();
    for (auto i : 0..3) { l.push(i) catch return; }
    for (auto x : l) {
        l.push(x * 10) catch return;
    }
}
```

Collect what you want to add and add it after the loop, or leave the loop right after the change (`break` or `return`); both are accepted.

Your own types can use the same words after the parameter list: `T* at(i64 i) borrows { ... }` and `!void push(T v) invalidates { ... }`. As with `move`, the check follows variable names: a pointer stored in a struct field or copied through a function call is not tracked.

## What the compiler does not check

| Problem | What happens |
|---|---|
| Use of a variable after `free`, `destroy`, `deinit` | **checked**: a compile error |
| Use through a copy of the pointer or through a field | not checked (use `DebugAllocator`) |
| A pointer into a local escaping the function | **checked**: a compile error |
| A pointer into a `List`/`Map` used after `push`/`put` | **checked**: a compile error |
| Double `free` of one variable | **checked**: a compile error |
| A leak (forgot `free`/`deinit`) | silent; the memory is released when the process exits |
| Going out of bounds of a slice or array | **checked**: a panic with file and line |
| Going out of bounds through a pointer | not checked |
| Division by zero | **checked**: a panic with file and line |

The discipline is simple: write `defer` right after allocating, pass the allocator down, and create an arena if you do not want to count individual `free`s.

## Choosing an allocator

- A simple program that needs one or two objects → `c_allocator()` and `defer`.
- Many small allocations with a common lifetime → `Arena`.
- The heap must not be touched, or memory is limited → `FixedBuf`.
- You need statistics, debugging or special rules → your own `Allocator`.

## What next

- Containers that take an allocator: [collections](collections.md).
- How `defer` works: [control flow](control-flow.md#defer-and-errdefer).
- Handling `OutOfMemory`: [errors and optional values](errors-and-optionals.md).
