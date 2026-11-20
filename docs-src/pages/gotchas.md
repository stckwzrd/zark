---
title: Pitfalls and FAQ
order: 42
section: Reference
description: Common beginner mistakes in Vibe, non-obvious behavior, language limitations and answers to the "why is it so" questions
---

This page collects what is not obvious: places where you can make a mistake and places where Vibe works differently from the languages you are used to. Every pitfall has an example. If you got a strange result or an error, look here.

## Numbers

### A literal is not checked against the range

```vibe run
void main() {
    const u8 b = 300;
    const i8 c = 200;
    println(b, c);
}
```

The extra bits are silently dropped. Watch the range of the type yourself.

### Integers overflow without a warning

```vibe run
void main() {
    const u8 a = 250;
    const auto b = a + 10;
    println(b);
    const i32 i = 2147483647;
    println(i + 1);
}
```

The result wraps around within the type. To catch it, build with `--check-overflow` (a panic with file and line) or compute in a wider type.

### Integer division by zero crashes the program

```vibe run exit
void main() {
    const auto a = 10;
    const auto z = a - 10;
    println(a / z);
}
```

This is a hardware exception, not an `error`. `vibe run` shows `error: error.Signaled`. Check the divisor before dividing.

### `/` on integers drops the fraction

`7 / 2` is `3`, and `-7 / 2` is `-3` (towards zero). For a fractional result convert: `7 as f64 / 2 as f64`.

### Floating-point literals hide imprecision

`0.1 + 0.2` is printed as `0.3` because the output goes through `%g`. But `0.1 + 0.2 == 0.3` is `false`. Compare floats with a tolerance.

### Narrowing and a change of sign only through `as`

`const i32 small = big;` will not compile. This is deliberate: "**Conversions are visible**".

### `300 as u8` from a literal

A literal in `as` is handled as a constant and may not be truncated. To check the behavior, put the number in a variable: `auto n = 300; n as u8` gives 44.

## Strings

### `{` in a string opens an interpolation

```vibe run
void main() {
    println("{"key": 1}");
}
```

The compiler took `{"key"...` for an interpolation of the string `"key"`, and instead of JSON you got an unexpected output. Write a literal brace as `{{` and `}}`:

```vibe run
void main() {
    println("{{\"key\": 1}}");
}
```

### Interpolation works only in print functions

`const auto s = "n = {n}";` is an error. Build a string value with `bprint` or `sprint` (see [strings](strings.md#building-strings)).

### You cannot modify a literal

```vibe run exit
void main() {
    auto s = "abc";
    s[0] = 65;
}
```

Writing into a literal crashes the program. Copy into a buffer.

### `str` is bytes, not characters

`"привет".len` is `12`, not `6`. Indexing gives bytes. For ASCII everything is simple; for other scripts you have to parse UTF-8 by hand.

### A slice of a string does not end with a zero byte

`puts(s[0..2].ptr)` will print the whole original string. For C use `to_cstr` or `dupz` (see [C](c-interop.md#strings-at-the-boundary)).

### There is no `+` for strings

Joining is done with `bprint` / `sprint`. There are no `split`, `join`, `replace`, `to_upper`; you write them yourself (recipes in [strings](strings.md)).

### A wrong format is printed as `<bad format>`

The specification is checked when printing, not at compile time. An unknown letter (`{n:b}`) or a format that does not suit the type gives `<bad format>` in the output, and the program goes on.

### There is no binary output

The format `{n:b}` is not supported: the allowed ones for integers are `d`, `i`, `u`, `x`, `X`, `o`, `c`.

## Variables and scopes

### A parameter is a copy

```vibe run
void f(i64 x) {
    x = 5;
}

void main() {
    auto n = 1;
    f(n);
    println(n);
}
```

Parameters and variables are mutable, but the function changes its own copy. To forbid changing a parameter, write `const i64 x`. To change the caller's data, pass a pointer.

### The same name twice in one block

```vibe error fragment
const auto x = 1;
const auto x = 2;
```

In a nested block you can shadow, in the same one you cannot.

### A variable hides a function

`const auto max = 5;` makes the call `max(1, 2)` impossible in that block.

### The names from the prelude are taken

You cannot declare functions `max`, `min`, `abs`, `sort`, `swap`, `run`, `env`, `arg`, `cstr`: "duplicate function". Choose other names.

### Global strings are not initialized

`str name = "x";` at the top level stays empty, and `auto name = "x";` is rejected. Assign at the start of `main`.

### A global array requires an initializer

`i64[3] arr;` at the top level without `= ...` does not compile. Write `i64[3] arr = [0, 0, 0];`.

### A `const` with a function call is evaluated every time

`const auto K = next();` at the top level is a substitution of the expression, and the side effect fires at every use.

## Control flow

### A forgotten `;`

Every statement ends with `;`. Without it the compiler stops at the next token:

```vibe error
void main() {
    const auto total = 1
    println(total);
}
```

### `if` is not an expression

`auto x = if (a) { 1 } else { 2 };` is an error. Use `match` (`match a { true => 1, false => 2 }`) or a variable declared in advance.

### In a `catch` block an expression must come last

A block that ends with a `match` or `if` as a statement does not count as a value. Put the result in a variable and make it the last line.

### The condition must be `bool`

`if (n)` and `while (p)` do not work. Write `n != 0` and `p != null`.

### No `0..=n`, `a, b = b, a`, `x++` as an expression

This is deliberate: one form per action. `x++` and the compound assignments (`+= -= *= /= %= |= &= ^= <<= >>=`) exist, but only as statements.

### `break` and `continue` name a loop through a label

To leave an outer loop, label it (`outer: for (...)`) and write `break outer;`. Without a label they affect the nearest loop.

### A `match` statement does not have to be complete

A forgotten variant causes no error: nothing simply happens. For a `match` expression, exhaustiveness is checked.

### A function without a `return` on all paths compiles

```vibe run
i64 f(i64 n) {
    if (n > 0) { return 1; }
    return 0;
}

void main() {
    println(f(1), f(-1));
}
```

The compiler does not check that all paths return a value. Always end a function with a `return`.

## Errors and optional values

### `catch` and `orelse` take everything to the right

`f(5) catch 0 + 100` is `f(5) catch (0 + 100)`, the result is `5`, not `105`. Use parentheses: `(f(5) catch 0) + 100`.

### `?` only in a function with `!T`

In an ordinary function `?` is not allowed: there is nowhere to propagate to.

### You cannot ignore a `!T`

`f()` without `?`, `catch` or `_ =` does not compile.

### `?T` is not compared with `null`

For `?T` use `orelse`, `is .None`, `match`. Only ordinary pointers can be compared with `null`.

### `catch return)` in parentheses

In a call argument, `catch return` before the closing parenthesis is not parsed. Put the result in a variable on a separate line.

## Types and structs

### A struct literal only with a capital letter

`point{ .x = 1 }` is not recognized: `T{` is taken as a literal when the type name starts with a capital letter.

### Missing fields are zeros

`P{ .x = 1 }` zeroes the other fields, and a typo in a field name is the only thing the compiler will catch.

### There is no `==` for structs and arrays

Compare fields and elements by hand, or define `operator==` on the struct.

### Structs and arrays are copied

Assignment and passing to a function copy everything. For shared work take a pointer or a slice.

### A method changes even a `const` object

```vibe run
struct C {
    i64 n;
    void inc() { this->n += 1; }
}

void main() {
    const auto c = C{ .n = 0 };
    c.inc();
    println(c.n);
}
```

The compiler does not check mutability at a method call: it passes a pointer. Declare the method `const` to forbid changing fields inside it.

### `.Name` needs a context

`const auto x = .Red;` does not compile: it is unclear whose variant this is. Write `Color::Red` or `const Color x = .Red;`.

### `number as Enum` is not checked

`7 as Color` gives a value "not from the list".

### You cannot assign numbers to enum variants

The numbers always go from zero in order.

## Functions and closures

### A closure cannot be returned

The context of a closure lives on the stack of the function where it is written. If you return it, you get garbage. Pass it only down.

### `fn(A) -> R` and `fn[](A) -> R` are different types

An ordinary function cannot be passed where a closure is expected, and the other way round.

### Inferred type parameters do not see an array literal

`first([1, 2])` will not infer `T`. Put the array in a variable and pass the slice `a[..]`, or write `first<i64>([1, 2])`.

### The `Ord` constraint does not fit strings

`T: Ord` accepts only numbers and characters. Strings are compared only with `==`.

### You cannot call a function in a `const` array size

`i64[K] a;` needs a compile-time constant.

## Memory

### Only going out of bounds of a slice and an array is checked

Going out through a pointer, use-after-free, a double `free`, leaks and dangling pointers to the stack are not detected.

### `FixedBuf.reset()` invalidates what was handed out

Everything handed out before `reset` must not be used.

### An arena does not free one by one

`free` on an arena does nothing. The memory returns at `deinit()`.

### A `List` without `init` does not work

A zero `List` has no allocator, and `push` on it will crash. Always call `List<T>::init(a)`.

### A pointer to a `List` element is invalid after `push`

The buffer may move. Take the pointer when you have finished adding.

### `Map`: keys are not copied, no `remove`, the order is undefined

If a key is built in a temporary buffer, use `a.dup(key)`.

### `sizeof` takes a type

`sizeof(buf)` does not work. Write `sizeof(u8[256])`.

## Modules

### A plain import "leaks"

A file imported without `as` puts all its names into the common namespace, and they are visible from all the files of the program.

### One file, one name

You cannot attach `util.vibe` as `a` and as `b` in one program.

### Unreachable code is not checked

Functions that cannot be reached from `main` are not compiled: an error in them goes unnoticed until they are called.

## FAQ

### Why are there no exceptions?

The rule "no hidden control flow". An error is a value, visible in the signature (`!T`) and at the call site (`?`, `catch`). `defer` and `errdefer` replace `finally`.

### Why is there no inheritance or macros, and so little overloading?

The rule "one action, one form". `+` on numbers always adds, a method is called by the type of the object, and the code looks the way it executes. Operators can be defined only on your own structs, as ordinary methods (see [structs](structs-unions-enums.md#operator-overloading)); there is no implementation inheritance, and there are no macros.

### Why is there no ternary operator?

`match` and an ordinary variable solve the same thing in one way. Since `match` is an expression, it can stand to the right of `=`.

### Why does `List::init` need an allocator?

So that the caller decides where the memory lives: the heap, an arena, a buffer on the stack. This is where the rule "no hidden allocations" comes from.

### What does "nothing allocates secretly" mean?

Not a string, not interpolation, not a closure, not `println` calls `malloc`. If there is no allocator in the code, nothing happens on the heap.

### How do I return several values?

Through a small struct. There are no tuples.

### How do I bring in a C library?

`extern` + `.c`/`.o`/`-l...` on the command line. See [interoperating with C](c-interop.md).

### How do I debug?

`println` and `eprintln` are the first tool. For a panic, look at the location (file and line) in the message. For the build: `vibe ir` shows the LLVM IR, `vibe tokens` shows the tokens, `--time` shows the time of the phases (see [tooling](tooling.md)).

### How do I find out what exactly is compiled?

`vibe ir main.vibe` prints the resulting LLVM IR. Only reachable functions are generated.

### Where is the source code of the standard library?

In `std/std.vibe` of the repository. You can read it as a sample of idiomatic code.

### Can I write without `main`?

For tests, yes (`vibe test`). To run, `main` is needed.

## What next

- Detailed pages on each topic go in order in the side menu.
- A short memo: the [cheat sheet](cheatsheet.md).
