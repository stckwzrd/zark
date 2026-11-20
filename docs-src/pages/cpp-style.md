---
title: Vibe for C++ programmers
order: 3
section: Start
description: Vibe syntax through the eyes of a C++ programmer: types first, template, methods inside struct, lambdas, for with parentheses and a list of differences from C++
---

Vibe is written almost like C++: types go first, generics use `template` and `<...>`, methods live inside `struct`, and a lambda capture is `[&k]`. This page shows all the essentials and lists how the language differs from C++.

## Declarations: the type comes first

```vibe run
const i64 LIMIT = 4;
i64 counter = 0;

i64 add(i64 a, i64 b) {
    return a + b;
}

i32 main() {
    auto n = add(2, 3);
    const i64 k = 10;
    i64 acc;
    acc = n * k;
    counter++;
    println(n, k, acc, LIMIT, counter);
    return 0;
}
```

The rules:

- The type is written before the name: `i64 x = 5;`. You can write `auto` instead of a type.
- Variables and parameters are **mutable** by default. `const` makes a value immutable.
- The result of a function stands before its name. A function without a result is `void`.
- The semicolon is mandatory, as in C++. It is not needed after the `}` of a block, function or `struct`.
- `nullptr` is the same as `null`.

Types: `T*` is a pointer, `T[]` a slice, `T[N]` an array, `!T` an error, `?T` an optional value. A number or constant in brackets is always an array size: `i64[4]`, `Point[4]`.

## Structs and methods inside struct

```vibe run
struct Point {
    i64 x;
    i64 y;

    i64 len2() const { return x * x + y * y; }
    void move(i64 dx, i64 dy) { x += dx; this->y += dy; }
    static Point origin() { return Point{}; }
}

i32 main() {
    auto p = Point{ .x = 3, .y = 4 };
    p.move(1, 1);
    println(p.len2(), p, Point::origin());
    return 0;
}
```

- Methods live inside `struct`. The fields are available by the bare name (`x`) and through `this->x` (or `this.x`). A local variable with the same name shadows the field.
- `static` declares a function without `this`: `Point::origin()`.
- `const` after the parameter list forbids the method to change fields through `this` (assignment and `+=` give an error). It also cannot call a non-const method through `this`.
- A literal with dots, `Point{ .x = 3 }`, zeroes the other fields, as in C++. `Point{}` has all fields zero.

## Union, enum and `::`

```vibe run
union Shape {
    f64 Circle;
    i64 Rect;
    Empty;
}

enum Color { Red, Green }

f64 area(Shape s) {
    return match s {
        .Circle(r) => r * r * 3.0,
        .Rect(w) => w as f64,
        .Empty => 0.0,
    };
}

i32 main() {
    Shape s = Shape::Circle(2.0);
    Color c = Color::Green;
    println(area(s), c);
    return 0;
}
```

The variants of a union are written like fields: `type Name;`. A variant without data is simply `Name;`. `::` is equivalent to `.`: `Color::Green`, `net::connect(...)`, `Point::origin()`.

## Templates

```vibe run
struct Pair<A, B> {
    A first;
    B second;
    A get_first() { return first; }
}

template<T: Ord> T largest(T a, T b) {
    if (a > b) { return a; }
    return b;
}

i32 main() {
    auto q = Pair<i64, str>{ .first = 7, .second = "seven" };
    println(q.get_first(), q);
    println(largest(3, 9), largest<f64>(2.5, 1.5));
    return 0;
}
```

The parameters of generic functions are written in `template<...>`, and those of generic types right after the name: `struct Pair<A, B>`. Constraints: `T: Ord`. Explicit arguments: `largest<f64>(...)`, `List<i64>::init(a)`.

## Control flow

In `if` and `while` the condition is in parentheses, and the curly braces remain mandatory.

```vibe run
i64 sum(i64[] xs) {
    i64 total = 0;
    for (i64 x : xs) { total += x; }
    return total;
}

i32 main() {
    i64[4] arr = [1, 2, 3, 4];
    i64 acc = 0;
    for (i64 i = 0; i < 10; i++) {
        if (i % 2 == 0) { continue; }
        acc += i;
    }
    for (i64 i : 0..3) { acc += i; }
    acc <<= 1;
    acc |= 1;
    println(sum(arr[..]), acc);
    return 0;
}
```

The forms of `for`:

- `for (T x : seq)` iterates over an array, slice or list;
- `for (T i : a..b)` is a range from `a` to `b`, with `b` excluded;
- `for (T i = a; i < b; i++)` and `i <= b`, with a step of only `i++`, `++i` or `i += 1`. It is the same range. Write any other C loops with `while`.

`++`, `--` and all the compound assignments are there: `+= -= *= /= %= |= &= ^= <<= >>=`. `i++` is a statement, not an expression.

A loop can carry a label (`outer: for (...)`) for `break outer;` and `continue outer;`.

`match` stays as it was, as do `defer`, `errdefer`, `?`, `catch`, `orelse`, `is`, string interpolation and `as`.

## Errors and optional values

```vibe run
!i64 parse(str s) {
    if (s.len == 0) { return error.Empty; }
    return parse_int(s);
}

?i64 find(i64[] xs, i64 want) {
    for (i64 i = 0; i < xs.len; i++) {
        if (xs[i] == want) { return i; }
    }
    return nullptr;
}

i32 main() {
    i64[3] xs = [4, 5, 6];
    println(parse("12") catch -1, parse("") catch -1);
    println(find(xs[..], 6) orelse -1, find(xs[..], 9) orelse -1);
    return 0;
}
```

## Lambdas

The capture is written as in C++, `[&k]`: variables are captured **by reference**, the context lives on the stack, and a closure must not be returned from a function.

```vibe run
i32 main() {
    i64 n = 10;
    i64 calls = 0;
    auto add = [&n, &calls](i64 x) -> i64 {
        calls++;
        return x + n;
    };
    println(add(5), add(6), calls);
    return 0;
}
```

The type of a closure is written `fn[](i64) -> i64`, and that of a function `fn(i64) -> i64`.

## Modules

```vibe file=cpp_lib.vibe
i64 twice(i64 x) { return x * 2; }
```

```vibe run
import "cpp_lib.vibe" as lib;

i32 main() {
    println(lib::twice(21));
    return 0;
}
```

## What is not there

- There is no `class` or `public:`, no implicit destructors and no inheritance. Constructors, operator overloading and interfaces do exist (see [structs, unions and enums](structs-unions-enums.md)).
- In a cast, a pointer type is written as a prefix: `p as *u8`.

## Table of differences

| C++ | Vibe |
|---|---|
| `int`, `long`, `double` | `i32`, `i64`, `f64` |
| `T* p`, `const T& r` | `T* p`; there are no references, only pointers and slices |
| `std::vector<T>` | `List<T>` with an explicit allocator: `List<T>::init(a)` |
| `std::string`, `std::string_view` | `str`: a slice of bytes, strings do not own memory |
| `try`/`catch`, `throw` | `!T`, `error.Name`, `?` and `catch` |
| `std::optional<T>` | `?T` |
| `std::variant`, `switch` | `union` and `match` |
| `new`/`delete`, RAII | `a.create<T>()`, `defer a.destroy(p)` |
| `std::cout << x` | `println(x)` and `"{x}"` in strings |
| `(T)x`, `static_cast<T>(x)` | `x as T` |
| `x ? a : b` | `match` |
