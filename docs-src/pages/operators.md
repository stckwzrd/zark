---
title: Operators and expressions
order: 13
section: Language
description: Arithmetic, comparisons, logic, bitwise operators, assignment, precedence, as, pointers and slices in Vibe
---

Vibe has few operators and no overloading of the built-in ones: `+` always means adding numbers. Every action on a value is visible in the code.

## Arithmetic

| Operator | What it does |
|---|---|
| `+` `-` `*` | addition, subtraction, multiplication |
| `/` | division (for integers the fraction is dropped towards zero) |
| `%` | remainder (the sign matches the sign of the dividend) |
| `-x` | negation |

```vibe run
void main() {
    println(7 + 3, 7 - 3, 7 * 3);
    println(7 / 2, -7 / 2, 7.0 / 2.0);
    println(7 % 3, -7 % 3, 7 % -3);
}
```

Both operands must have the same type. An integer can be widened implicitly, but it cannot be mixed with a float:

```vibe error fragment
const i64 a = 5;
const f64 b = 2.0;
println(a + b);
```

Convert explicitly: `a as f64 + b`.

Strings are not joined with operators:

```vibe error fragment
println("a" + "b");
```

Joining is done with interpolation and a [buffer](strings.md#building-strings): `"{a}{b}"`.

Integer division by zero panics (see [types](types.md#overflow)); floating-point division by zero gives `inf` or `nan`.

## Comparisons

`==` `!=` `<` `<=` `>` `>=` give `bool`.

```vibe run
void main() {
    println(1 == 1, 1 != 2, 3 < 2, 3 >= 3);
    println(1.5 < 2.5, 'a' < 'b');
    println("abc" == "abc", "abc" != "abd");
}
```

Only `==` and `!=` are defined for strings. You cannot order strings with `<`:

```vibe error fragment
println("abc" < "abd");
```

Chains of comparisons like `1 < 2 < 3` do not work: the result of `1 < 2` is a `bool`, not a number.

```vibe error fragment
println(1 < 2 < 3);
```

Enum values and pointers can be compared too:

```vibe run
enum Color { Red, Green }

void main() {
    const Color c = .Green;
    println(c == .Green, c != .Red);
    i64* p = null;
    println(p == null);
}
```

`==` is not defined for structs: compare the fields by hand.

## Logic

`&&` (and), `||` (or), `!` (not). The operands must be `bool`; numbers are not accepted as conditions.

Evaluation is **lazy**: the right-hand side runs only if it is needed for the result.

```vibe run
bool noisy(str name, bool v) {
    println("called {name}");
    return v;
}

void main() {
    const auto a = false && noisy("first", true);
    const auto b = true || noisy("second", true);
    const auto c = true && noisy("third", false);
    println(a, b, c);
}
```

This lets you write a guard and a check in one condition:

```vibe run
void main() {
    const auto s = "x";
    auto i = 5;
    if (i < s.len && s[i] == 'x') {
        println("found");
    } else {
        println("no, but no error either");
    }
}
```

```vibe error fragment
println(!5);
```

## Bitwise operators

| Operator | Action |
|---|---|
| `&` | and |
| `\|` | or |
| `^` | exclusive or |
| `~x` | bitwise not |
| `<<` `>>` | shifts |

```vibe run
void main() {
    println(5 & 3, 5 | 3, 5 ^ 3, ~5);
    println(1 << 4, 0xff >> 4);
    println(-5 >> 1, 7 as u64 >> 1);
}
```

A right shift is arithmetic for signed types (the sign is kept) and logical for unsigned ones. The shift count is masked to the type width, so a count that is too large never gives undefined behavior.

> **Note:** unlike C, the bitwise `&`, `|`, `^` bind **tighter** than comparisons. The expression `x & 1 == 0` reads as `(x & 1) == 0`, and no parentheses are needed.

```vibe run
void main() {
    const auto n = 6;
    if (n & 1 == 0) { println("even"); }
    const auto flags = 0b1010;
    println(flags & 0b0010 != 0, flags & 0b0100 != 0);
}
```

## Assignment

`=` puts a value into a variable, a field, an array element or the target of a pointer. Assignment is a statement, not an expression: you cannot write `a = b = 0`.

The compound forms: `+=` `-=` `*=` `/=` `%=` `|=` `&=` `^=` `<<=` `>>=`.

```vibe run
void main() {
    auto x = 10;
    x += 5;
    x -= 3;
    x *= 2;
    x /= 4;
    x %= 4;
    x |= 8;
    x <<= 1;
    x++;
    println(x);
}
```

`x++` and `x--` exist too, but they are statements, not expressions: you cannot write `y = x++`. There is no simultaneous assignment `a, b = b, a`; use a temporary variable or `swap`:

```vibe run
void main() {
    auto a = 1;
    auto b = 2;
    swap(&a, &b);
    println(a, b);
}
```

`_ = expression` evaluates the expression and discards the result. You can call a function that returns a number and ignore the result even without `_`. But a `!T` does not pass without `_`: `_ =` shows that you are ignoring the error on purpose.

```vibe run
!i64 load() { return 42; }

void main() {
    _ = load();
    println("result discarded");
}
```

Ignoring a `!T` without `_`, `?` or `catch` is a [compile error](errors-and-optionals.md#you-cannot-ignore-an-error).

## Unary operators

| Form | Meaning |
|---|---|
| `-x` | negation |
| `!b` | logical not |
| `~x` | bitwise not |
| `&x` | the address of a variable |
| `*p` | the value at an address |

`&` takes the address only of something that lives in memory: a variable, a field, an element. The result of `&x` has the type `T*`.

## Postfix forms

These operations stand right after an expression and bind the tightest:

| Form | Meaning |
|---|---|
| `f(a, b)` | call |
| `x[i]` | index |
| `x[a..b]` | slice |
| `x.name` | a field or a method (`->` and `::` mean the same) |
| `x?` | propagate the error |

```vibe run
struct Box { i64[3] items; }

void main() {
    auto b = Box{ .items = [10, 20, 30] };
    println(b.items[1], b.items[0..2], b.items.len);
    const auto p = &b;
    println(p.items[2]);
}
```

Chains like `a.b.c(1)[2].d` are read left to right.

## `as` and precedence

`as` converts a value to another type (see [types](types.md#conversions-as)). It binds more weakly than the unary operators but more strongly than arithmetic:

```vibe run
void main() {
    const auto a = 5;
    println(-a as f64 / 2 as f64);
    println(a as f64 / 2 as f64);
    println(1 + 2 as f64);
}
```

Here `-a as f64` means `(-a) as f64`, and `1 + 2 as f64` means `1 + (2 as f64)`, so the result is a float.

For a pointer: `&x as *u8` means `(&x) as *u8`.

> **Gotcha:** with `catch` and `orelse` write parentheses: `(f() catch 0) as i64`. Without them `catch` takes everything to its right.

## Precedence

From the weakest to the strongest:

| Level | Operators |
|---|---|
| 1 (weakest) | `catch`, `orelse` |
| 2 | `\|\|` |
| 3 | `&&` |
| 4 | `==` `!=` `<` `<=` `>` `>=` |
| 5 | `\|` |
| 6 | `^` |
| 7 | `&` |
| 8 | `<<` `>>` |
| 9 | `+` `-` |
| 10 | `*` `/` `%` |
| 11 | `as` |
| 12 | unary `-` `!` `~` `&` `*` |
| 13 (strongest) | postfix: `()` `[]` `[a..b]` `.f` `->f` `::f` `?` |

All binary operators are left-associative: `10 - 3 - 2` is `(10 - 3) - 2`.

```vibe run
void main() {
    println(1 + 2 * 3, (1 + 2) * 3);
    println(10 - 3 - 2);
    println(1 << 2 + 1);
    println(2 * 3 % 4);
    println(true || false && false);
}
```

`1 << 2 + 1` is `1 << (2 + 1)`, because `+` is stronger than a shift. When in doubt, add parentheses: they are free.

### `catch` and `orelse` take everything to the right

`catch` and `orelse` are the weakest operators, so their right-hand side is the whole expression to the end:

```vibe run
!i64 f(i64 n) {
    if (n < 0) { return error.Neg; }
    return n;
}

?i64 g(i64 n) {
    if (n < 0) { return null; }
    return n;
}

void main() {
    println(f(5) catch 0 + 100);
    println(g(5) orelse 0 + 100);
    println((f(5) catch 0) + 100);
}
```

The first two lines print `5`: a successful result on the left stays as it is, and `0 + 100` is the fallback value that was not needed. If you wanted to add 100 to the result, you need parentheses (the third line).

## `is`: testing a variant

`x is .Variant` gives a `bool`: it tests an enum or the tag of a union.

```vibe run
enum State { Idle, Busy }

union Msg {
    str Text;
    Quit;
}

void main() {
    const State s = .Busy;
    const Msg m = .Quit;
    println(s is .Busy, s is .Idle);
    println(m is .Quit, m is .Text);
}
```

To extract the contents, use [`match`](control-flow.md#match).

## What next

- Conditions and loops: [control flow](control-flow.md).
- How `?`, `catch` and `orelse` work with errors: [errors and optional values](errors-and-optionals.md).
