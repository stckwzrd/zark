---
title: Errors and optional values
order: 17
section: Language
description: The type !T, error.Name, ?, catch, errdefer, the type ?T and orelse in Vibe, with analysis of typical patterns
---

Vibe has no exceptions. An error is an ordinary value that a function returns alongside its result. Everything is visible in the signature and at the call site.

There are two types for two different situations:

| Type | Meaning | When to use |
|---|---|---|
| `!T` | a value of `T` **or an error** with a name | the operation could break: a file, parsing, running out of memory |
| `?T` | a value of `T` **or nothing** | absence is a normal outcome: a lookup, an optional field |

## Errors: `!T`

A function declares that it can fail by putting `!` before the result type. To return an error, write `return error.Name`.

```vibe run
!i64 safe_div(i64 a, i64 b) {
    if (b == 0) { return error.DivByZero; }
    return a / b;
}

void main() {
    println(safe_div(10, 2) catch -1);
    println(safe_div(1, 0) catch -1);
}
```

The name of an error is made up on the spot: `error.DivByZero`, `error.NotFound`. There is no need to declare lists of errors in advance. The same name in different functions means the same error.

A plain value `T` fits wherever `!T` is expected (an implicit conversion), so in the successful case just write `return value`.

If you do not need a result but an error is possible, write `!void`:

```vibe run
!void check(i64 n) {
    if (n < 0) { return error.Negative; }
}

void main() {
    check(5) catch println("bad");
    check(-5) catch println("bad");
}
```

A `!T` value can be put into a variable and printed. It is printed as the value or as `error.Name`:

```vibe run
!i64 f(i64 n) {
    if (n == 0) { return error.Zero; }
    return n;
}

void main() {
    const auto a = f(0);
    const auto b = f(2);
    println(a, b);
}
```

You cannot use such a value as an ordinary number: it has to be "unwrapped" first:

```vibe error
!i64 f() { return 1; }

void main() {
    const i64 x = f();
}
```

## You cannot ignore an error

If you call a function that returns `!T` and do nothing with the result, that is a compile error. You cannot forget about a failure:

```vibe error
!i64 f() { return 1; }

void main() {
    f();
    println("next");
}
```

Choose: propagate (`?`), handle (`catch`) or deliberately discard (`_ =`).

## Propagating: `?`

`expression?`: if there is an error inside, the function **immediately returns that same error** to its caller (running `defer` and `errdefer`). If there is a value, it is extracted.

```vibe run
!i64 parse(str s) {
    if (s.len == 0) { return error.Empty; }
    return parse_int(s);
}

!i64 sum(str a, str b) {
    const auto x = parse(a)?;
    const auto y = parse(b)?;
    return x + y;
}

void main() {
    println(sum("10", "32") catch -1);
    println(sum("10", "") catch -1);
    println(sum("10", "x") catch -1);
}
```

`?` can be used only in a function that itself returns `!T`. Otherwise it is unclear where to propagate to:

```vibe error
!i64 f() { return 1; }
i64 g() { return f()?; }

void main() {
    println(g());
}
```

Chains like `a()?.b()?` are read left to right: every `?` is a point of possible exit.

### `main` with `!void`

If `main` returns `!void`, an uncaught error ends the program with code 1 and prints `error: Name`:

```vibe run exit
!void load() {
    return error.FileMissing;
}

!void main() {
    println("start");
    load()?;
    println("we will not get here");
}
```

## Handling: `catch`

`expression catch fallback` gives the result of the expression when it succeeds, and `fallback` on an error.

```vibe run
!i64 f(i64 n) {
    if (n == 0) { return error.Zero; }
    return n * 10;
}

void main() {
    println(f(3) catch 0, f(0) catch 0);
    println(parse_int("12") catch -1, parse_int("12x") catch -1);
}
```

### With the name of the error

`catch |e| { ... }` gives access to the error. The block must **produce a value** (the last expression of the block) or **leave** the function or loop with `return`, `break`, `continue` or `panic`.

```vibe run
!i64 f(i64 n) {
    if (n == 0) { return error.Zero; }
    if (n < 0) { return error.Negative; }
    return n;
}

void main() {
    const auto r = f(-1) catch |e| {
        println("error: {e}");
        -1;
    };
    println(r);
}
```

You can pick a value by the kind of error with a comparison. `if` is a statement, so the value is declared in advance:

```vibe run
!i64 f(i64 n) {
    if (n == 0) { return error.Zero; }
    return error.Other;
}

void main() {
    const auto r = f(0) catch |e| {
        auto v = 200;
        if (e == error.Zero) { v = 100 };
        v;
    };
    println(r);

    const auto r2 = f(1) catch |e| {
        const auto m = match e {
            error.Zero => 1,
            _ => 2,
        };
        m;
    };
    println(r2);
}
```

A block that gives no value is an error. An expression must come last:

```vibe error
!i64 f() { return error.X; }

void main() {
    const auto v = f() catch |e| {
        println(e);
    }
}
```

### Leaving instead of a value

In a `catch` branch you can leave the current function or loop:

```vibe run
!i64 f(i64 n) {
    if (n == 0) { return error.Zero; }
    return n;
}

i64 twice(i64 n) {
    const auto v = f(n) catch return -1;
    return v * 2;
}

void main() {
    println(twice(0), twice(4));
    for (auto i : 0..3) {
        const auto v = f(i) catch continue;
        println("v = {v}");
    }
}
```

### `catch` for `!void`

If the expression returns nothing, an action simply follows `catch`:

```vibe run
!void f() { return error.Boom; }

void main() {
    f() catch println("handled");
    f() catch |e| println("caught {e}");
    println("end");
}
```

### Deliberately discarding: `_ =`

```vibe run
!i64 risky() { return error.Fail; }

void main() {
    _ = risky();
    println("the error was ignored explicitly");
}
```

This is allowed, but rarely needed in practice: more often you write `catch 0` or `catch return`.

## `errdefer`: rollback only on error

`errdefer` runs only when the function exits **with an error**. It is meant for rolling back partially built state. A plain `defer` always runs (see [control flow](control-flow.md#defer-and-errdefer)).

```vibe run
!i64 make(i64 n) {
    errdefer println("rollback: make({n}) failed");
    defer println("in any case: finished make({n})");
    if (n < 0) { return error.Negative; }
    return n * 2;
}

void main() {
    println(make(5) catch 0);
    println(make(-1) catch 0);
}
```

The rule works both for an error that arrived through `?` and for a `return g()` that turned out to be an error:

```vibe run
!void inner() { return error.OutOfRange; }

!void outer() {
    errdefer println("outer: rollback");
    inner()?;
    println("not printed");
}

void main() {
    outer() catch |e| println("main caught {e}");
}
```

A typical use: you allocated two things, the second failed, so you free the first.

## Errors in the standard library

The functions of the standard library return errors with clear names:

| Function | Errors |
|---|---|
| `parse_int(s)` | `error.InvalidNumber` |
| `List.pop()`, `List.last()` | `error.Empty` |
| `Map.get(k)` | `error.NotFound` |
| `read_line(buf)` | `error.EndOfFile` |
| `bprint(buf, ...)`, `to_cstr` | `error.NoSpace` |
| `read_file(a, path)` | `error.FileNotFound`, `error.ReadFailed` |
| `write_file(path, data)` | `error.CannotOpen`, `error.WriteFailed` |
| `env(name)` | `error.NotFound` |
| `run(a, argv)` | `error.Signaled` and process start errors |
| `a.alloc(n)`, `List.push(v)` | `error.OutOfMemory` |

The full table is in the [reference](stdlib.md).

```vibe run
void main() {
    println(parse_int("42") catch -1);
    const auto e = parse_int("abc") catch |e| {
        println("not a number: {e}");
        0;
    };
    println(e);
}
```

## Optional values: `?T`

`?T` means "either a value or nothing". The type `?T` is the same as `Option<T>` from the standard library (a union with the variants `Some` and `None`).

A value `T` and `null` convert implicitly into `?T`:

```vibe run
?i64 find(i64[] xs, i64 want) {
    for (auto [i, x] : xs) {
        if (x == want) { return i; }
    }
    return null;
}

void main() {
    const auto xs = [5, 8, 13];
    const auto a = find(xs[..], 13);
    const auto b = find(xs[..], 99);
    println(a, b);
}
```

### `orelse`: a fallback value

`a orelse b` is the value of `a`, or `b` if it is empty. The right-hand side can be an exit: `return`, `break`, `continue`.

```vibe run
?i64 find(i64[] xs, i64 want) {
    for (auto [i, x] : xs) {
        if (x == want) { return i; }
    }
    return null;
}

i64 index_or_bust(i64[] xs, i64 v) {
    const auto i = find(xs, v) orelse return -7;
    return i * 10;
}

void main() {
    const auto xs = [5, 8, 13];
    println(find(xs[..], 8) orelse -1);
    println(find(xs[..], 99) orelse -1);
    println(index_or_bust(xs[..], 13), index_or_bust(xs[..], 0));
    for (auto i : 0..3) {
        const auto v = find(xs[..], i * 4 + 5) orelse continue;
        println("found at {v}");
    }
}
```

> **Gotcha:** the fallback has the same type as the one inside: `?i64 orelse "a"` is a type error.

### Testing and taking apart

```vibe run
?i64 pick(i64 n) {
    if (n > 0) { return n; }
    return null;
}

void main() {
    const auto a = pick(5);
    const auto b = pick(-5);
    println(a.is_some(), b.is_some(), b.unwrap_or(9));
    println(a is .Some, b is .None);
    match a {
        .Some(v) => println("value {v}");
        .None => println("empty");
    }
    const ?i64 c = .Some(5);
    const ?i64 d = .None;
    println(c, d);
}
```

Methods: `is_some()` and `unwrap_or(fallback)`. The patterns `.Some(v)` and `.None` work in [`match`](control-flow.md#match-as-an-expression), and `is` tests the variant.

### A pointer or `?T*`

For "a pointer that may be absent" use `?T*`. You cannot compare a value of type `?T` with `null` directly (`x == null`): use `orelse`, `is .None` or `match`.

```vibe run
struct Node { i64 v; }

?Node* find(Node[] xs, i64 v) {
    for (auto i : 0..xs.len) {
        if (xs[i].v == v) { return &xs[i]; }
    }
    return null;
}

void main() {
    auto xs = [Node{ .v = 1 }, Node{ .v = 2 }];
    const auto p = find(xs[..], 2) orelse return;
    p.v = 20;
    println(xs[1].v);
    println(find(xs[..], 5) is .None);
}
```

An ordinary pointer `T*` can itself be `null` and is compared with `null` directly.

## Nesting: `!?T`

An operation that can break and can also return "nothing": `!?T`. The `!` is unwrapped first, then the `?`:

```vibe run
!?i64 lookup(str key) {
    if (key.len == 0) { return error.EmptyKey; }
    if (key == "a") { return 1; }
    return null;
}

void main() {
    const auto a = lookup("a") catch return;
    const auto b = lookup("zz") catch return;
    println(a orelse -1, b orelse -1);
}
```

## Choosing between `!T` and `?T`

Ask: "if there is no result, is that normal or is it a failure?"

- A search in a list did not find the element: that is normal → `?T`.
- A file did not open, a number did not parse, memory ran out: a failure → `!T`.
- If the **reason** matters, you need a `!T` with a descriptive error name.

## `panic` and `assert`

For programmer errors (a violated invariant) there are `panic("message")` and `assert(condition)`: they print the location and end the program with code 1. They do not replace `!T`.

```vibe run panic
void main() {
    const auto n = 3;
    assert(n > 0);
    println("the first assert passed");
    assert(n > 5);
    println("not printed");
}
```

## What next

- How to release resources on any exit: [control flow](control-flow.md#defer-and-errdefer).
- Out-of-memory errors: [memory and allocators](memory.md).
- Checking errors in tests: [testing](testing.md).
