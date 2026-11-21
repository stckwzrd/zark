---
title: Compile-time evaluation
order: 19.5
section: Language
description: comptime in Vibe: run ordinary functions while compiling, build lookup tables and check facts about types before the program exists
---

`comptime` runs a piece of your program **while the program is being compiled** and puts the result into the binary as a constant. It is the same language, with the same functions, loops and standard library: there is no second "macro language".

```vibe run
i64 fib(i64 n) {
    if (n < 2) { return n; }
    return fib(n - 1) + fib(n - 2);
}

void main() {
    println(comptime fib(30));
}
```

The call to `fib(30)` is not in the binary. The compiler built a small program, ran it, read the answer and inserted the number `832040`.

## What can be a comptime value

The result must be plain data: a number, `bool`, an enum, a `str`, or an array or struct made of those. A pointer or a slice of other data has no meaning in another process, so it is rejected:

```vibe error
i64* nothing() { return null; }

void main() {
    const auto x = comptime nothing();
}
```

## What a comptime expression can use

Functions, constants, types and other `comptime` values. It cannot use local variables or the type parameters of a generic, because there are no values for them yet:

```vibe error
void main() {
    auto n = 5;
    println(comptime n + 1);
}
```

## Lookup tables

The main use is a table that you would otherwise type by hand or fill at program start. The function that builds it is an ordinary function:

```vibe run
u32[256] make_crc() {
    u32[256] t;
    for (auto i : 0..256) {
        u32 c = i as u32;
        for (auto k : 0..8) {
            if (c & 1 == 1) { c = 0xEDB88320 ^ (c >> 1); } else { c = c >> 1; }
        }
        t[i] = c;
    }
    return t;
}

const auto CRC = comptime make_crc();

u32 crc(str s) {
    u32 c = 0xFFFFFFFF;
    for (auto b : s) { c = CRC[((c ^ b as u32) & 0xFF) as i64] ^ (c >> 8); }
    return ~c;
}

void main() {
    println(crc("123456789"));
}
```

The table lives in the read-only data of the program. `CRC[i]` reads one element; it does not copy the table.

Structs and strings work the same way:

```vibe run
struct Limits { i64 max_users; f64 ratio; bool strict; }

Limits defaults() { return Limits{ .max_users = 100, .ratio = 0.75, .strict = true }; }
str banner() { return "vibe"; }

void main() {
    const auto l = comptime defaults();
    println(l.max_users, l.ratio, l.strict, comptime banner());
}
```

## Checking facts at build time

A top-level `comptime` statement is evaluated before the program is built. If it panics or fails an `assert`, compilation stops. This is a static assertion:

```vibe error
struct Header { u8 kind; i64 length; }

comptime assert(sizeof(Header) == 9);

void main() {}
```

The message `assertion failed` comes from the compile-time run itself, followed by the line of the `comptime` expression.

Inside a function, `comptime` on a statement that returns nothing does the same thing at that point.

## Rules and costs

- **It really runs your code.** A comptime function can read files and print, like any other function. It runs with the checks of a normal build, so overflows, bounds and division by zero are panics and stop the compilation with a message.
- **Each `comptime` costs one extra compilation** of the program (about a tenth of a second for a small one). The same expression is run only once per build, however many times its constant is used.
- **Not in string interpolation.** Write `const auto x = comptime f();` and use `x` in the string.
- **Generics.** `sizeof(T)` is already known to the compiler, so you do not need `comptime` for it; `comptime` cannot see `T`.

## What next

- Constants and variables: [variables](variables.md).
- Why the compiler needs no special macro language: [how the compiler works](how-it-works.md).
