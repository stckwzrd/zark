---
title: Cheat sheet
order: 44
section: Reference
description: All of Vibe's syntax on one page: tables and short examples for quick lookup
---

A short memo. Details on each topic are behind the links.

## A program

```vibe run
void main() {
    println("Hello, Vibe!");
}
```

| Command | What it does |
|---|---|
| `vibe run f.vibe [-- args]` | build and run |
| `vibe build f.vibe [-o out] [--release]` | build an executable |
| `vibe test f.vibe` | run the `test` blocks |
| `vibe fmt [--check] f.vibe` | format |
| `vibe lsp` | the language server |
| `vibe ir f.vibe` | show the LLVM IR |

See [installation](getting-started.md) and [tooling](tooling.md).

## Lexical structure

| | |
|---|---|
| comments | `// line`, `/* block */` |
| end of a statement | `;` (not needed after the `}` of a block) |
| numbers | `42`, `0xff`, `0b101`, `0o17`, `1_000`, `3.14`, `1e9` |
| character | `'a'` is a `u8` number |
| strings | `"text"`, escapes `\n \t \r \0 \e \\ \" \' \{ \}` |
| interpolation | `"x = {expr}"`, literal braces `{{` `}}` |

See [lexical structure](lexical.md).

## Types

| | |
|---|---|
| integers | `i8 i16 i32 i64 isize`, `u8 u16 u32 u64 usize` |
| floating-point | `f32 f64` |
| other | `bool`, `void`, `str` (= `u8[]`) |
| pointer | `T*`, `void*`, `null` |
| slice / array | `T[]`, `T[N]` |
| error / optional | `!T`, `?T` |
| functions | `fn(A, B) -> R`, closure `fn[](A) -> R` |
| alias | `type Name = Type;` |
| SIMD | `f32x4`, `i32x8`, `u8x16`: `f32x4(a, b, c, d)`, `f32x4(x)`, `v[i]` |

See [types](types.md).

## Variables

```vibe run
const auto N = 4 * 2;
i64 counter = 0;

void main() {
    const auto a = 10;
    i64 b = 20;
    b += a;
    i32 zero;
    counter += 1;
    println(a, b, zero, N, counter);
}
```

A variable is mutable, `const` makes it immutable, `auto` infers the type, and without a value it is zero. See [variables](variables.md).

## Operators

| | |
|---|---|
| arithmetic | `+ - * / %`, `-x` |
| comparison | `== != < <= > >=` |
| logic | `&& \|\| !` (lazy, `bool` only) |
| bits | `& \| ^ ~ << >>` |
| assignment | `= += -= *= /= %= \|= &= ^= <<= >>=`, `x++`, `x--`, `_ = expression` |
| conversion | `x as T` |
| pointers | `&x`, `*p`, `p[i]`, `p + n`, `p.field` |
| slices | `x[a..b]`, `x[a..]`, `x[..b]`, `x[..]` |
| variant test | `x is .Variant` |
| error / optional | `f()?`, `f() catch v`, `f() catch \|e\| { ... }`, `x orelse v` |

Precedence, from weak to strong: `catch`/`orelse`, `||`, `&&`, comparisons, `|`, `^`, `&`, shifts, `+ -`, `* / %`, `as`, unary, postfix. See [operators](operators.md).

## Control flow

```vibe run
void main() {
    const auto n = 7;
    if (n > 5) { println("big"); } else { println("small"); }

    auto i = 0;
    while (i < 2) { i += 1; }

    for (auto k : 0..3) { print(k, ""); }
    println();
    for (auto [idx, v] : [10, 20]) { print("{idx}={v}", ""); }
    println();

    const auto word = match n {
        1, 2 => "few",
        _ => "many",
    };
    println(word, i);
}
```

| | |
|---|---|
| `if (c) { } else if (c) { } else { }` | the condition is `bool` only, the braces are mandatory |
| `while (c) { }` | a loop |
| `for (auto i : a..b) { }` | `a` inclusive, `b` not |
| `for (auto x : seq) { }`, `for (auto [i, x] : seq) { }` | an array, slice, `List` |
| `break`, `continue`, `return [e]` | exits; `outer: for ...` with `break outer;` leaves an outer loop |
| `match v { pat => e, ... }` | values, enums, strings, unions; `_` is the rest |
| `defer stmt`, `errdefer stmt` | run when leaving the block (`errdefer` only on an error) |

See [control flow](control-flow.md).

## Functions

```vibe run
i64 add(i64 a, i64 b) { return a + b; }
template<T: Ord> T largest(T a, T b) { if (a > b) { return a; } return b; }

void main() {
    const auto k = 10;
    const auto plus = [&k](i64 x) -> i64 { return x + k; };
    println(add(1, 2), largest(3, 9), plus(5));
}
```

| | |
|---|---|
| declaration | `Result name(Type p) { }` |
| generic | `template<T: Ord> T name(T x)`, constraints `Eq Ord Num Int Float` |
| explicit type | `name<i64>(...)` |
| closure | `[&capture](i64 x) -> i64 { }`, lives only down the stack |
| C | `extern i64 f(i64 x);`, `export void g() { }` |

See [functions](functions.md).

## Structs, unions, enums

```vibe run
struct Point {
    i64 x;
    i64 y;
    static Self new(i64 x, i64 y) { return Self{ .x = x, .y = y }; }
    i64 sum() { return this->x + this->y; }
}
enum Color { Red, Green }
union Shape { f64 Circle; Empty; }

void main() {
    const auto p = Point::new(1, 2);
    const Color c = .Green;
    const Shape s = .Circle(2.0);
    println(p.sum(), c, s);
    match s {
        .Circle(r) => println("r = {r}");
        .Empty => {}
    }
}
```

| | |
|---|---|
| literal | `P{ .x = 1, .y = 2 }`, `P{ .x = 1 }` (the rest zeroed), `P{}` |
| method | inside `struct`: `void m() { ... }`, `this` is a pointer |
| static | `static Self new() { ... }`, called as `P::new()` |
| enum | `.Name` (by context) or `Color::Red`; `as i64` |
| union | `.Name(payload)`, `.Name`; `match` with binding |
| generic | `struct Pair<A, B> { ... }`, `Pair<i64, str>{ ... }` |

See [structs, unions and enums](structs-unions-enums.md).

## Errors and optionals

```vibe run
!i64 half(i64 n) {
    if (n % 2 != 0) { return error.Odd; }
    return n / 2;
}

?i64 find(i64[] xs, i64 v) {
    for (auto [i, x] : xs) { if (x == v) { return i; } }
    return null;
}

void main() {
    println(half(8) catch 0, half(7) catch 0);
    println(find([4, 5], 5) orelse -1);
}
```

See [errors and optional values](errors-and-optionals.md).

## Memory

| | |
|---|---|
| allocators | `c_allocator()`, `FixedBuf::init(buf).allocator()`, `Arena::init(parent).allocator()` |
| allocate | `a.alloc<T>(n)?`, `a.create<T>()?`, `a.dup(s)?` |
| free | `a.free(s)`, `a.destroy(p)`, `arena.deinit()` |
| pattern | `auto x = a.alloc<T>(n)?;` and right away `defer a.free(x)` |

See [memory](memory.md).

## Collections

```vibe run
!void main() {
    auto xs = List<i64>::init(c_allocator());
    defer xs.deinit();
    xs.push(3)?;
    xs.push(1)?;
    xs.sort();
    println(xs.slice());

    auto m = Map<i64>::init(c_allocator());
    defer m.deinit();
    m.put("a", 1)?;
    println(m.get("a")?, m.has("b"));
}
```

See [collections](collections.md).

## Strings and output

| | |
|---|---|
| output | `print`, `println`, `eprint`, `eprintln` |
| into a buffer | `bprint(buf[..], "...")?`, `sprint(&list, "...")?` |
| formats | `{x:x}` `{x:08X}` `{x:6}` `{x:-6}` `{f:.2}` `{f:e}` `{c:c}` |
| strings | `s.len`, `s[i]`, `s[a..b]`, `==`, `str_find`, `str_trim`, `parse_int` |
| panic | `panic("msg {x}")`, `assert(cond)` |

See [strings](strings.md).

## Modules and C

```text
import "util.vibe";                 names go into the common namespace
import "util.vibe" as u;            u::name
vibe run main.vibe lib.c x.cpp -lm  C and C++ together
```

See [modules](modules.md) and [C](c-interop.md).

## Tests

```vibe test
test "arithmetic" {
    assert(1 + 1 == 2);
}
```

`vibe test main.vibe`. See [testing](testing.md).

## Pitfalls in one line

- A literal outside the range of its type is truncated silently, and integers overflow silently (unless you build with `--check-overflow`).
- Integer division by zero crashes the program.
- `catch` and `orelse` take everything to the right: use parentheses.
- `{` in a string is an interpolation, a literal brace is `{{`.
- A closure must not be returned, and functions without a `return` on all paths compile.
- The prelude names (`min`, `max`, `abs`, `sort`, `run`, `env`) are taken.

The full list: [pitfalls and FAQ](gotchas.md).
