---
title: Types
order: 11
section: Language
description: All Vibe types: integers, floats, bool, pointers, slices, arrays, str, error unions, functions, sizes and conversions
---

Vibe is statically typed. The type of every expression is known at compile time, and the memory layout is predictable: **what you see is what is in memory** (structs are laid out as in C).

## Overview

| Type | What it is | Size |
|---|---|---|
| `i8 i16 i32 i64` | signed integers | 1, 2, 4, 8 bytes |
| `u8 u16 u32 u64` | unsigned integers | 1, 2, 4, 8 bytes |
| `isize usize` | pointer-sized integers | 8 bytes |
| `f32 f64` | floating-point numbers | 4, 8 bytes |
| `bool` | `true` / `false` | 1 byte |
| `void` | "nothing" | none |
| `T*` | pointer to `T` | 8 bytes |
| `T[]` | slice: pointer and length | 16 bytes |
| `str` | the same as `u8[]` | 16 bytes |
| `T[N]` | an array of `N` elements | `N * sizeof(T)` |
| `!T` | a value of `T` or an error | depends on `T` |
| `?T` | a value of `T` or nothing | depends on `T` |
| `fn(A, B) -> R` | pointer to a function | 8 bytes |
| `struct`, `union`, `enum` | your own types | see [structs](structs-unions-enums.md) |

The size of any type is available through `sizeof`, and the alignment through `alignof`. Both are computed at compile time and have the type `u64`.

```vibe run
struct Pair { u8 a; i64 b; }

void main() {
    println(sizeof(i8), sizeof(i16), sizeof(i32), sizeof(i64));
    println(sizeof(f32), sizeof(f64), sizeof(bool));
    println(sizeof(u8*), sizeof(str), sizeof(i32[4]));
    println(sizeof(Pair), alignof(Pair), alignof(u8));
}
```

Note `Pair`: after the `u8` there are 7 bytes of padding, as in C.

## Integers

```vibe run
void main() {
    const i8 a = -128;
    const u8 b = 255;
    const i64 c = 9223372036854775807;
    const usize d = 1024;
    println(a, b, c, d);
}
```

A literal without a context is `i64`. A literal with a suitable context takes its type:

```vibe run
u8 takes_u8(u8 x) { return x; }

void main() {
    println(takes_u8(200));
    const auto n = 5;
    println(n * 1000000000000);
}
```

### Overflow

Integer arithmetic wraps around within the type, without a panic, like unsigned arithmetic in C:

```vibe run
void main() {
    const u8 u = 255;
    println(u + 1);
    const i8 i = 127;
    println(i + 1);
    const u32 z = 0;
    println(z - 1);
}
```

> **Gotcha:** overflow is not detected by default. Compile with `--check-overflow` to make `+`, `-` and `*` stop the program with a file and line, or compare in advance, or use a wider type.

When wrapping is what you want (hashes, counters, checksums), say so with `+%`, `-%` and `*%`: they always wrap, even under `--check-overflow`, and never trigger the "signed overflow is undefined" assumption of `--fast`.

```vibe run
void main() {
    u64 h = 14695981039346656037;
    for (auto c : "vibe") { h = (h ^ c as u64) *% 1099511628211; }
    println(h);
    const u8 big = 250;
    println(big +% 10);
}
```

Integer division by zero crashes the program (a processor signal): `vibe run` shows `error: error.Signaled`. Check the divisor yourself.

### Implicit widening

An integer is implicitly converted to a wider one **without loss**:

```vibe run
i64 wide(i64 x) { return x * 2; }

void main() {
    const i8 a = 5;
    const u16 b = 1000;
    println(wide(a), wide(b));
}
```

Narrowing, a change of sign and integer → float need an explicit `as`:

```vibe error fragment
const i64 big = 5;
const i32 small = big;
```

```vibe error fragment
const i32 n = 5;
const u32 u = n;
```

`as` is described in detail below, in the "Conversions" section.

## Floating-point numbers

```vibe run
void main() {
    const f64 a = 0.1 + 0.2;
    const f32 b = 1.0 / 3.0;
    println(a, b);
    println(a == 0.3);
}
```

Printing goes through `%g`: up to six significant digits. Floating-point division by zero does not crash:

```vibe run
void main() {
    f64 z = 0.0;
    println(1.0 / z, -1.0 / z);
}
```

You cannot mix `f32` and `f64` without `as`, and the same goes for integers and floats.

## bool

Only `true` and `false`. The conditions of `if` and `while` must be `bool`: "a nonzero number is true" does not work.

```vibe error fragment
const auto n = 1;
if (n) { println("yes"); }
```

Write an explicit comparison: `if (n != 0)`.

## void

A function without a return type returns `void`. You cannot declare a variable of that type.

## Pointers

`T*` is the address of a value of type `T`. Take an address with `&x`, read the value at an address with `*p`.

```vibe run
void main() {
    auto x = 10;
    const auto p = &x;
    *p = 42;
    println(x, *p);
}
```

Pointers have arithmetic: `p + n` moves by `n` **elements**, not bytes. Indexing `p[i]` is the same as `*(p + i)`.

```vibe run
void main() {
    auto arr = [10, 20, 30, 40];
    const auto p = &arr[0];
    println(p[0], p[2], *(p + 3));
    p[1] = 99;
    println(arr);
}
```

Fields are accessed through a pointer with a plain dot, with no need to dereference:

```vibe run
struct Point { i64 x; i64 y; }

void main() {
    auto pt = Point{ .x = 1, .y = 2 };
    const auto p = &pt;
    p.x = 100;
    println(pt.x, p.y);
}
```

> **Gotcha:** pointers are not checked: you can go out of bounds or use a pointer to a function that has already returned. For safe work with data, use slices.

### `void*` and `null`

`void*` is "any pointer". It converts implicitly to `T*` and back, which is needed for allocators and C. `null` is the null pointer; it can be assigned to any pointer or function.

```vibe run
void main() {
    i64* p = null;
    println(p == null);
    auto x = 5;
    p = &x;
    println(p == null, *p);
}
```

## Arrays `T[N]`

The size of an array is a compile-time constant (a number or a `const`). An array is a value: assignment copies all the elements.

```vibe run
const auto N = 3;

void main() {
    i64[N] a;
    println(a);
    a[0] = 7;
    a[2] = 9;
    const auto b = a;
    a[1] = 5;
    println(a, b, a.len);
    const auto lit = [1, 2, 3, 4];
    println(lit, lit.len);
}
```

`T[N] a;` without an initializer is filled with zeros. The literal `[1, 2, 3]` gives `i64[3]` unless the context suggests something else.

Going out of bounds is an emergency stop with the exact location. The check is on by default and is turned off by the `--release` flag:

```vibe run panic
void main() {
    const auto a = [1, 2, 3];
    auto i = 3;
    println(a[i]);
}
```

## Slices `T[]`

A slice is a "window" into someone else's memory: a pointer and a length. It owns nothing and frees nothing.

```vibe run
void main() {
    auto data = [1, 2, 3, 4, 5, 6];
    const i64[] all = data[..];
    const auto mid = data[1..4];
    const auto head = data[..2];
    const auto tail = data[4..];
    println(all, mid, head, tail);
    println(mid.len);
    mid[0] = 99;
    println(data);
}
```

The bounds of a slice include the start and exclude the end (like `a..b` in loops). All forms: `x[a..b]`, `x[a..]`, `x[..b]`, `x[..]`.

A slice can be made from an array, from another slice or from a pointer. For a pointer the end is mandatory because the length is unknown:

```vibe run
void main() {
    auto arr = [1, 2, 3, 4];
    const auto p = &arr[0];
    const auto s = p[0..3];
    println(s);
}
```

Where a slice is expected, an array literal becomes a slice over memory on the stack:

```vibe run
i64 total(i64[] xs) {
    auto t = 0;
    for (auto x : xs) { t += x; }
    return t;
}

void main() {
    println(total([1, 2, 3]));
    println(total([]));
}
```

> **Gotcha:** a slice does not extend the life of the data. A slice that points at a local array must not be returned from a function: the stack is freed after the return.

## str

`str` is the same thing as `u8[]`: a pointer to bytes and a length. A string is not a special type but a slice of bytes, so `.len`, indexing and slicing work:

```vibe run
void main() {
    const auto s = "hello";
    println(s.len, s[1], s[1..3]);
    println(s == "hello", s == "world");
}
```

These are bytes, not Unicode characters: a Cyrillic letter takes two bytes.

```vibe run
void main() {
    const auto s = "привет";
    println(s.len);
}
```

`==` on `str` compares the contents (with `memcmp` inside), not the addresses. More on the page [strings and formatting](strings.md).

## Error union `!T`

`!T` is either a value of `T` or an error. Described in detail in [errors and optional values](errors-and-optionals.md).

```vibe run
!i64 half(i64 n) {
    if (n % 2 != 0) { return error.Odd; }
    return n / 2;
}

void main() {
    println(half(10) catch -1, half(7) catch -1);
}
```

`T` converts implicitly to `!T`, and `error.Name` converts to any `!T`.

## Optional `?T`

`?T` is a value or "nothing". It is the `Option<T>` of the standard library:

```vibe run
?i64 first_even(i64[] xs) {
    for (auto x : xs) {
        if (x % 2 == 0) { return x; }
    }
    return null;
}

void main() {
    println(first_even([3, 5, 6, 8]) orelse -1);
    println(first_even([3, 5]) orelse -1);
}
```

## Function pointers

The type `fn(A, B) -> R` is the address of a function. For a function without a result write `fn(A, B) -> void`.

```vibe run
i64 double(i64 x) { return x * 2; }
i64 negate(i64 x) { return -x; }

i64 apply(fn(i64) -> i64 f, i64 x) { return f(x); }

void main() {
    println(apply(double, 21), apply(negate, 5));
    fn(i64) -> i64 op = double;
    println(op(4));
    op = negate;
    println(op(4));
}
```

A function pointer does not hold an environment. If a function needs the variables around it, use a [closure](functions.md#closures).

## Type aliases

`type Name = Type;` gives a new name, not a new type: the two are interchangeable.

```vibe run
type Bytes = u8[];
type Callback = fn(i64) -> i64;
type Grid = i64[2][3];

i64 call(Callback cb, i64 n) { return cb(n); }
i64 inc(i64 n) { return n + 1; }

void main() {
    const Bytes b = "abc";
    println(b.len, call(inc, 9));
    Grid g;
    g[1][2] = 7;
    println(g);
}
```

## SIMD vectors

A SIMD vector holds several numbers that one instruction processes at once. The types are named after the element and the number of lanes: `f32x4`, `f32x8`, `f64x2`, `f64x4`, `i32x4`, `i32x8`, `i64x2`, `u8x16` and so on (2 to 32 lanes, at most 32 bytes).

```vibe run
f32 dot(f32[] a, f32[] b) {
    f32x8 acc = f32x8(0.0);
    for (auto i : 0..a.len / 8) {
        f32x8 x = *(&a[i * 8] as *f32x8);
        f32x8 y = *(&b[i * 8] as *f32x8);
        acc = acc + x * y;
    }
    f32 s = 0.0;
    for (auto k : 0..8) { s += acc[k]; }
    return s;
}

void main() {
    f32x4 a = f32x4(1.0, 2.0, 3.0, 4.0);
    f32x4 b = f32x4(10.0);
    println(a * b + a, -a, a[2]);
    f32[8] u = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0];
    println(dot(u[..], u[..]));
}
```

- `f32x4(a, b, c, d)` builds a vector from its lanes, and `f32x4(x)` puts the same value into every lane.
- `+ - * /` (and `& | ^` on integer vectors) work lane by lane; a scalar on one side is spread over all lanes (`a * 2.0`). Unary `-` works too. Vectors cannot be compared with `==` or `<`.
- `v[i]` reads and writes a lane. Loading a vector from memory with `*(p as *f32x4)` does not require alignment.
- A program that uses vectors is built through LLVM automatically (the own backend has no vector instructions). With `--release` a loop like the one above runs several times faster than the scalar one.

## Conversions: `as`

All the implicit conversions (there are few):

- an integer → a wider integer without loss;
- `T` → `!T` and `T` → `?T`;
- `error.X` → `!T`;
- `null` → a pointer, a function or `?T`;
- `T*` ↔ `void*`;
- an array literal → a slice.

Everything else is done explicitly, with `as`:

| From → to | Example | Result |
|---|---|---|
| integer → integer | `300 as u8` (from a variable) | the high bits are dropped |
| integer → float | `n as f64` | the nearest value |
| float → integer | `3.99 as i64` | the fractional part is dropped: 3 |
| float → float | `x as f32` | with rounding |
| pointer → pointer | `p as *u8` | the same address |
| pointer ↔ integer | `p as i64` | the address as a number |
| enum ↔ integer | `Color.Blue as i64` | the ordinal number |
| `T[]` → `T*` | `s as *T` | a pointer to the first element |

```vibe run
enum Color { Red, Green, Blue }

void main() {
    const auto big = 300;
    println(big as u8, -1 as u32, -5 as i8);
    println(3.99 as i64, -3.99 as i64, 7 as f64 / 2 as f64);
    println(Color::Blue as i64, 1 as Color);
    const f32 f = 0.1;
    println(f as f64);
}
```

`as` binds more weakly than the unary operators, unlike in C++: `-a as i64` means `(-a) as i64`, and `&x as *u8` means `(&x) as *u8`. More on the [operators](operators.md#as-and-precedence) page.

## What next

- How to declare values and why `const` exists: [variables and constants](variables.md).
- Operators and precedence: [operators](operators.md).
- Composite types: [structs, unions and enums](structs-unions-enums.md).
