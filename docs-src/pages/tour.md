---
title: Quick tour
order: 2
section: Start
description: The whole Zark language on one page: short programs with real output
---

This page shows all the essentials in one sitting. The details of each topic are on separate pages, linked at the end of the sections.

## Variables

Variables are mutable by default, and `const` makes them immutable. You can write `auto` instead of a type: it is inferred from the value.

```zark run fragment
const auto a = 10;
auto b = 20;
b += a;
const f64 pi = 3.14159;
println("a = {a}, b = {b}, pi = {pi}");
```

Trying to change a `const` variable does not compile:

```zark error fragment
const auto a = 10;
a = 11;
```

More: [variables and constants](variables.md).

## Numbers and conversions

Integer and floating-point types are named as in Rust: `i8..i64`, `u8..u64`, `f32`, `f64`. Only lossless widening is implicit; everything else goes through `as`.

```zark run fragment
const i32 small = 1000;
const i64 big = small;
const auto back = big as i32;
const auto f = 7 as f64 / 2.0;
const auto t = 3.99 as i64;
println(big, back, f, t);
```

Narrowing without `as` does not compile:

```zark error fragment
const i64 big = 1000;
const i32 small = big;
```

More: [types](types.md), [operators](operators.md).

## Strings and formatting

`str` is a slice of bytes. Inside `"..."` you can write any expression in curly braces, and a format after a colon.

```zark run fragment
const auto name = "Zark";
const auto n = 255;
println("{name} has {name.len} letters");
println("hex {n:x}, padded {n:08X}, width [{n:6}] [{n:-6}]");
println("pi ~ {3.14159265:.3}");
```

More: [strings and formatting](strings.md).

## Control flow

```zark run fragment
for (auto i : 1..6) {
    if (i % 2 == 0) {
        println("{i} is even");
    } else {
        println("{i} is odd");
    }
}
auto n = 3;
while (n > 0) {
    n -= 1;
}
println("n = {n}");
```

More: [control flow](control-flow.md).

## Functions

```zark run
i64 square(i64 x) {
    return x * x;
}

void greet(str name) {
    println("Hello, {name}!");
}

void main() {
    greet("Zark");
    println(square(12));
}
```

More: [functions](functions.md).

## Structs and methods

```zark run
struct Point {
    i64 x;
    i64 y;
    static Point new(i64 x, i64 y) {
        return Point{ .x = x, .y = y };
    }

    i64 len2() {
        return this->x * this->x + this->y * this->y;
    }
}

void main() {
    const auto p = Point::new(3, 4);
    println("{p.x},{p.y} -> {p.len2()}");
    println(p);
}
```

More: [structs, unions and enums](structs-unions-enums.md).

## Enums, unions and match

```zark run
enum Color { Red, Green, Blue }

union Shape {
    f64 Circle;
    i64 Rect;
    Empty;
}

str name(Color c) {
    return match c {
        .Red => "red",
        .Green => "green",
        .Blue => "blue",
    }
}

f64 area(Shape s) {
    return match s {
        .Circle(r) => 3.14 * r * r,
        .Rect(w) => w as f64,
        .Empty => 0.0,
    }
}

void main() {
    println(name(.Green));
    println(area(.Circle(2.0)), area(.Rect(5)), area(.Empty));
}
```

## Errors

An error is a value. A function that can fail returns `!T`. The `?` operator propagates the error upwards, and `catch` handles it.

```zark run exit
!i64 parse(str s) {
    if (s.len == 0) { return error.Empty; }
    return parse_int(s);
}

!void main() {
    println(parse("42")?);
    println(parse("") catch -1);
    println(parse("abc") catch |e| { println("error: {e}"); 0; });
    const auto n = parse("x")?;
    println(n);
}
```

The last line ends the program with an error: `main` returned `error.InvalidNumber`.

More: [errors and optional values](errors-and-optionals.md).

## Optional values

`?T` is a value or nothing. `orelse` supplies a fallback.

```zark run
?i64 find(i64[] items, i64 want) {
    for (auto [i, x] : items) {
        if (x == want) { return i; }
    }
    return null;
}

void main() {
    const auto xs = [5, 8, 13];
    println(find(xs[..], 13) orelse -1);
    println(find(xs[..], 99) orelse -1);
}
```

## Memory

Nothing allocates by itself. The heap is reachable only through an allocator that you pass explicitly.

```zark run
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    auto list = List<i64>::init(a);
    for (auto i : 1..6) { list.push(i * i)?; }
    println(list.slice());
}
```

`defer` runs when the scope exits: `arena.deinit()` frees everything at once. More: [memory and allocators](memory.md).

## Generics

```zark run
template<T: Ord> T largest(T a, T b) {
    if (a > b) { return a; }
    return b;
}

struct Pair<A, B> { A first; B second; }

void main() {
    println(largest(3, 9), largest(2.5, 1.5));
    const auto p = Pair<i64, str>{ .first = 1, .second = "one" };
    println(p.first, p.second);
}
```

## Closures

A closure lists explicitly which variables it uses. The context lives on the stack, and nothing is allocated.

```zark run
i64 apply(fn[](i64) -> i64 f, i64 x) {
    return f(x);
}

void main() {
    const auto k = 10;
    auto calls = 0;
    const auto add = [&k, &calls](i64 x) -> i64 {
        calls += 1;
        return x + k;
    };
    println(apply(add, 1), apply(add, 2), calls);
}
```

## Tests

```zark test
i64 add(i64 a, i64 b) { return a + b; }

test "adds" {
    assert(add(2, 3) == 5);
}

test "zero is neutral" {
    assert(add(7, 0) == 7);
}
```

More: [tests](testing.md).

## Modules

A file is brought in with `import`. With `as`, its names get a prefix:

```zark file=geometry.zk
struct Rect { i64 w; i64 h; }

i64 area(Rect r) { return r.w * r.h; }
```

```zark run
import "geometry.zk" as geo;

void main() {
    const auto r = geo::Rect{ .w = 3, .h = 4 };
    println(geo::area(r));
}
```

More: [modules and imports](modules.md).

## Calling C

```zark run
extern i32 atoi(u8* s);

void main() {
    println(atoi("1234") + 1);
}
```

More: [interoperating with C](c-interop.md).

## Where to go next

- Coming from C++? The differences are collected on the page [Zark for C++ programmers](cpp-style.md).
- To go deeper, follow the pages of the "Language" section in order: [lexical structure](lexical.md), [types](types.md) and on.
- To see finished programs: [cookbook](cookbook.md).
- If something behaves unexpectedly: [pitfalls and FAQ](gotchas.md).
