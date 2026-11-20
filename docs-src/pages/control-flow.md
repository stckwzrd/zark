---
title: Control flow
order: 14
section: Language
description: if, while, for, break, continue, match and defer in Vibe: all the forms with examples and edge cases
---

There are few control constructs, and each has one form. The condition is written in parentheses, and the braces of the block are always mandatory, even for a single statement.

## `if` / `else`

```vibe run
void main() {
    const auto n = 7;
    if (n > 10) {
        println("greater than ten");
    } else if (n > 5) {
        println("between five and ten");
    } else {
        println("five or less");
    }
}
```

The condition must be `bool`. A number or a pointer is not accepted as a condition; an explicit comparison is needed:

```vibe error fragment
const auto n = 5;
if (n) { println("yes"); }
```

The braces are mandatory:

```vibe error fragment
const auto n = 5;
if (n > 3) println("yes");
```

`if` is a statement, not an expression: `auto x = if ...;` is not written. When you need to choose a value by a condition, use [`match`](#match-as-an-expression) or a variable declared in advance:

```vibe run
void main() {
    const auto n = 7;
    auto kind = "few";
    if (n > 5) { kind = "many"; }
    println(kind);

    const auto size = match n > 5 {
        true => "big",
        false => "small",
    };
    println(size);
}
```

## `while`

```vibe run
void main() {
    auto i = 0;
    while (i < 3) {
        println("i = {i}");
        i += 1;
    }

    auto n = 100;
    while (n > 1) {
        n /= 3;
    }
    println(n);
}
```

An infinite loop is written as `while (true) { ... }` and left with `break` or `return`.

## `for` over a range

`for (auto i : a..b)` iterates over the integers from `a` inclusive to `b` **exclusive**. If `a >= b`, the loop does not run at all. The end of the range is evaluated once before the loop starts.

```vibe run
void main() {
    for (auto i : 0..4) {
        println(i);
    }
    for (auto i : 5..5) { println("not printed"); }
    for (auto i : 3..0) { println("not printed either"); }
    const auto n = 3;
    auto sum = 0;
    for (auto i : 1..n + 1) { sum += i; }
    println(sum);
}
```

There is no inclusive form `0..=3`: write `0..4`. There is no reverse iteration either. For a backwards pass use `while`:

```vibe run
void main() {
    auto i = 3;
    while (i > 0) {
        i -= 1;
        println(i);
    }
}
```

A range exists only inside `for`: you cannot store `0..3` in a variable.

The loop variable is immutable inside the body:

```vibe error fragment
for (auto i : 0..3) {
    i += 1;
}
```

## `for` over a collection

`for (auto x : seq)` iterates over the elements of an array, a slice or any value with a `slice()` method (for example `List`). `for (auto [i, x] : seq)` adds the index.

```vibe run
void main() {
    const auto arr = [10, 20, 30];
    for (auto x : arr) { println(x); }
    for (auto [i, x] : arr) { println("{i}: {x}"); }
    for (auto c : "abc") { println(c); }

    auto list = List<i64>::init(c_allocator());
    defer list.deinit();
    list.push(7) catch return;
    list.push(8) catch return;
    for (auto [i, v] : list) { println(i, v); }
}
```

A string is iterated byte by byte: here `c` is a number of type `u8` (97, 98, 99). The element is a **copy**. To change elements in place, go by index:

```vibe run
void main() {
    auto xs = [1, 2, 3];
    for (auto i : 0..xs.len) {
        xs[i] *= 10;
    }
    println(xs);
}
```

You cannot iterate over a number:

```vibe error fragment
for (auto x : 5) { println(x); }
```

## `break` and `continue`

`break` leaves the nearest loop, and `continue` moves to the next iteration. To leave an outer loop, put a label in front of it and name the label in `break` or `continue`.

```vibe run
void main() {
    auto i = 0;
    while (true) {
        i += 1;
        if (i == 2) { continue; }
        if (i > 4) { break; }
        println("i = {i}");
    }

    for (auto a : 0..3) {
        for (auto b : 0..3) {
            if (b == 1) { break; }
            println("a={a} b={b}");
        }
    }
}
```

A label is written in front of `for` or `while`:

```vibe run
void main() {
    auto found = 0;
    rows: for (auto i : 0..5) {
        for (auto j : 0..5) {
            if (j == 3) { continue rows; }
            if (i == 2) { break rows; }
            found += 1;
        }
    }
    println(found);
}
```

`break` and `continue` also work inside `match`, affecting the enclosing loop:

```vibe run
void main() {
    for (auto x : [1, 2, 3, 4, 5]) {
        match x {
            2 => continue;
            4 => break;
            _ => {}
        }
        println(x);
    }
}
```

## `match`

`match` compares a value with patterns from top to bottom and runs the first branch that fits. There is no fall-through between branches.

```vibe run
enum Dir { North, East, South, West }

void main() {
    const Dir d = .East;
    match d {
        .North => println("up");
        .East, .West => println("sideways");
        _ => println("down");
    }

    const auto n = 3;
    match n {
        1, 2 => println("few");
        3 => {
            println("three");
        }
        _ => {}
    }

    const auto cmd = "stop";
    match cmd {
        "go" => println("going");
        "stop" => println("stopping");
        _ => println("unclear");
    }
}
```

What can be matched: integers, characters (`'a'`), enums, strings (via `==`) and unions. A pattern can be a literal or a constant, and several patterns in one branch are separated by commas. There are no ranges (`1..5`) in patterns.

The branch `_` means "everything else". In a `match` **statement** it is optional: if nothing fits, nothing happens.

```vibe run
void main() {
    const auto n = 5;
    match n {
        1 => println("a");
    }
    println("after match");
}
```

### Unions and binding the payload

For a union, the pattern `.Variant(name)` binds the contents of the variant to a name. The bound value is read-only and lives inside the branch.

```vibe run
union Shape {
    f64 Circle;
    i64 Rect;
    Empty;
}

void describe(Shape s) {
    match s {
        .Circle(r) => println("circle r = {r}");
        .Rect(w) => println("square {w}x{w}");
        .Empty => println("empty");
    }
}

void main() {
    describe(.Circle(1.5));
    describe(.Rect(4));
    describe(.Empty);
}
```

If the payload is not needed, write the variant without parentheses: `.Empty` (for a variant without a payload) or `.Circle(_)`.

### `match` as an expression

`match` can stand to the right of `=`, in a `return`, in an argument. The branches are then expressions (or blocks whose value is the last expression), and all are converted to one type.

```vibe run
enum Level { Low, Mid, High }

i64 score(Level l) {
    return match l {
        .Low => 1,
        .Mid => 5,
        .High => 10,
    }
}

void main() {
    const auto x = 4;
    const auto word = match x {
        1 => "one",
        2 => "two",
        _ => "many",
    };
    println(word, score(.High));

    const auto doubled = match x {
        4 => {
            const auto t = x * 2;
            t + 1;
        },
        _ => 0,
    };
    println(doubled);
}
```

A `match` expression has a hard requirement: it must be **exhaustive**. Cover all the variants or add `_`:

```vibe error
enum D { N, E }

void main() {
    const D d = .E;
    const auto v = match d {
        .N => 1,
    };
    println(v);
}
```

A branch may give no value at all and instead leave the function or loop with `return`, `break` or `continue`:

```vibe run
i64 first_positive(i64[] xs) {
    for (auto x : xs) {
        const auto ok = match x > 0 {
            true => x,
            false => continue,
        };
        return ok;
    }
    return -1;
}

void main() {
    println(first_positive([-3, 0, 4, 9]));
    println(first_positive([-1, -2]));
}
```

## `defer` and `errdefer`

`defer statement` postpones a statement until the current block is left: through the end of the block, `return`, `break` or `continue`. Several `defer`s run in reverse order, the last declared first.

```vibe run
void main() {
    defer println("declared first, runs last");
    defer println("declared second, runs first");
    println("body");
}
```

`defer` is tied to the **block**, not to the function. In a loop it fires on every iteration:

```vibe run
void main() {
    for (auto i : 0..3) {
        defer println("end of iteration {i}");
        if (i == 1) { continue; }
        println("body {i}");
    }
}
```

A block can be deferred too:

```vibe run
i64 work() {
    auto x = 1;
    defer {
        println("cleanup, x = {x}");
        x = 100;
    }
    return x;
}

void main() {
    println(work());
}
```

The value of `return` is computed **before** the `defer`, so `work()` returned `1` even though the `defer` later wrote 100 into `x`.

The typical use is to release a resource right after acquiring it:

```vibe run
!void main() {
    auto list = List<i64>::init(c_allocator());
    defer list.deinit();
    list.push(1)?;
    list.push(2)?;
    println(list.slice());
}
```

### `errdefer`

`errdefer` is the same, but only on the paths where the function returned an **error** (`return error.X`, `?` on an error and so on). It does not run on a successful exit. It is ideal for rolling back something partially built:

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

More about errors: [errors and optional values](errors-and-optionals.md).

## What is missing

- The ternary operator `a ? b : c` (use `match` or `if`).
- `do { } while` and `loop`.
- `switch` with fall-through.
- `goto`.
- Ranges in `match` and inclusive ranges `0..=n`.

All of this is deliberate: one form for one action.

## What next

- How to organize code into functions: [functions](functions.md).
- Composite types and taking them apart: [structs, unions and enums](structs-unions-enums.md).
