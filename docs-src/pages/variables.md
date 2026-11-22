---
title: Variables and constants
order: 12
section: Language
description: Declaring variables, auto, const, global variables and constants, scope, zero initialization and the immutability rules in Zark
---

A variable is declared as in C++: the type first, then the name. You can write `auto` instead of the type. The choice between "can change" and "cannot change" is made by `const`, and the compiler checks it.

## `const`: an immutable variable

```zark run
void main() {
    const auto x = 10;
    const auto name = "Zark";
    const f64 pi = 3.14159;
    println(x, name, pi);
}
```

The type can be omitted: it is inferred from the value. An explicit type is needed when the value does not determine it by itself (for example, the literal `5` can be any integer) or when you want to pin the type down:

```zark run
void main() {
    const auto a = 5;
    const u8 b = 5;
    const f32 c = 5.0;
    println(sizeof(i64), a, b, c);
}
```

A `const` variable cannot be changed:

```zark error fragment
const auto x = 1;
x = 2;
```

```zark error fragment
const auto x = 1;
x += 1;
```

## A mutable variable

```zark run
void main() {
    auto count = 0;
    count = 5;
    count += 1;
    count *= 2;
    println(count);
}
```

Without `const` a variable is mutable. If it is never changed, the compiler stays silent: there are no warnings about unused variables.

## Zero initialization

A variable without an initial value is filled with zeros (zero bits). This applies to integers, arrays and structs alike:

```zark run
struct P { i64 x; str name; }

void main() {
    i64 n;
    f64 f;
    bool b;
    str s;
    i32[4] arr;
    P p;
    println(n, f, b, s.len, arr);
    println(p.x, p.name.len);
}
```

An empty string is a null pointer with length 0; an empty pointer is `null`. So you cannot "forget" to initialize a variable: reading it is always defined.

> **Tip:** writing `const T x;` without a value is useless: you will never be able to assign anything. A variable without a value does not need `const`.

## Constness goes all the way through

`const` forbids not only assigning the variable itself, but also changing struct fields and array elements **through it**:

```zark error
struct P { i64 x; }

void main() {
    const auto p = P{ .x = 1 };
    p.x = 2;
}
```

```zark error fragment
const auto a = [1, 2, 3];
a[0] = 5;
```

To change the contents, do not write `const`:

```zark run
struct P { i64 x; }

void main() {
    auto p = P{ .x = 1 };
    p.x = 2;
    auto a = [1, 2, 3];
    a[0] = 5;
    println(p.x, a);
}
```

What lies **behind a pointer or a slice** is not frozen by `const`, though: the restriction applies only to the binding itself.

```zark run
void bump(i64[] xs) {
    for (auto i : 0..xs.len) { xs[i] += 1; }
}

void main() {
    auto data = [1, 2, 3];
    const auto view = data[..];
    bump(view);
    view[0] = 100;
    println(data);
}
```

Here `view` is declared with `const`, but `view[0] = 100` works: the slice points at the mutable `data`. The function `bump` received a slice and changed the caller's data.

Function parameters are mutable, but they are a copy: the caller will not see the changes. To forbid changing a parameter, write `const`: `i64 f(const i64 x)`. To change the caller's data, take a pointer or a slice.

## Scope

A variable lives until the end of the block `{ ... }` where it is declared. The same name cannot be declared twice in one block:

```zark error fragment
const auto x = 1;
const auto x = 2;
```

In a nested block a name can be **shadowed**; after leaving the block the outer one is visible again:

```zark run
void main() {
    const auto x = 1;
    {
        const auto x = 2;
        println("inside {x}");
    }
    println("outside {x}");
    for (auto i : 0..2) {
        const auto x = i * 10;
        println(x);
    }
}
```

Loop variables (`for (auto i : ...)`) also live only inside the loop.

### Do not name a variable like a function

A local variable hides a function with the same name, and calling it later in the block becomes impossible:

```zark error
void main() {
    const auto max = 5;
    println(max(1, 2));
}
```

Do not name variables `min`, `max`, `abs`, `sort` and so on: those are functions of the [standard library](stdlib.md).

## Global `const`: a compile-time constant

A top-level `const` is evaluated at compile time and substituted in place. A constant has no address and cannot be changed.

```zark run
const auto A = 3;
const auto B = A * 2 + 1;
const auto NAME = "zark";
const auto RATE = 1.5;
const auto MASK = 0xff & 0x0f;

void main() {
    i64[B] arr;
    println(A, B, NAME, RATE, MASK);
    println(arr.len);
}
```

If a constant is needed as an array size, it must be computable at compile time: numbers, arithmetic on them and other constants. If the initializer contains a function call, `const` turns into "an expression that is substituted at every use" and is recomputed each time:

```zark run
auto n = 0;

i64 next() {
    n += 1;
    return n;
}

const auto K = next();

void main() {
    println(K, K, K);
}
```

> **Gotcha:** this is not what you expect from a constant. Do not put calls of functions with side effects into a `const`; for such values, create a variable inside a function.

You cannot assign to a constant:

```zark error
const auto K = 5;

void main() {
    K = 6;
}
```

The type can be given explicitly: `const u8 LIMIT = 200;`. With `auto` a number gets its type from how it is used.

> **Note:** full compile-time evaluation (`comptime`) does not exist yet; it is among the [plans](how-it-works.md#what-next).

## Global variables

A variable without `const` declared at the top level is a global mutable variable. The initializer is mandatory and must be a constant expression: a number, arithmetic on numbers, `true`/`false`, `null`. You cannot use another global variable in the initializer.

```zark run
auto calls = 0;
i64 limit = 100;
i64 total = 2 + 3;
auto ready = true;

void hit() {
    calls += 1;
}

void main() {
    hit();
    hit();
    hit();
    println(calls, limit, total, ready);
}
```

> **Gotcha:** a global variable of type `str` with an initializer (`str name = "x";`) currently stays an empty string. With `auto` (`auto name = "x";`) the compiler reports the error "not a compile-time constant". If you need a global string, declare `str name = "";` and assign the value at the start of `main`.

You can take the address of a global variable; it lives in the program's memory for the whole run.

Global variables are shared mutable state. Use them sparingly: more often it is better to pass a value or a pointer as a parameter.

## Order of declarations

The order of functions, structs and constants at the top level does not matter: you can call a function before it is declared in the file.

```zark run
void main() {
    println(later(5));
}

i64 later(i64 x) { return x + LIMIT; }

const auto LIMIT = 100;
```

## What next

- How operators work and their precedence: [operators](operators.md).
- What happens to the memory a variable points at: [memory](memory.md).
