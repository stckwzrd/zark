---
title: Lexical structure
order: 10
section: Language
description: Comments, literals, escapes, the end of a statement and string interpolation in Zark
---

This page describes the pieces the source text is made of: comments, numbers, strings, names and the rule for "the end of a statement".

## Files and the entry point

A source file is plain UTF-8 text with the extension `.zk`. A program starts at the function `main`. It can return nothing, an `i32` (the exit code) or `!void` (an error that ends the program).

```zark run
void main() {
    println("the smallest program");
}
```

The exit code can be returned as a number:

```zark run exit
i32 main() {
    println("exiting with code 3");
    return 3;
}
```

## Comments

There are two kinds: the line comment `//` and the block comment `/* ... */`.

```zark run
void main() {
    // a line comment runs to the end of the line
    const auto a = 1 /* a block comment can sit right inside an expression */ + 2;
    /*
       a block comment can span
       several lines
    */
    println(a);
}
```

> **Note:** block comments do not nest: the first `*/` closes the comment.

## End of a statement

Every statement ends with a semicolon, as in C++. It is not needed after the closing `}` of a block, function, `struct`, `enum`, `union`, `if`, `while`, `for` or `match`.

A statement can be wrapped any way you like: only `;` ends it.

```zark run
i64 sum3(i64 a, i64 b, i64 c) { return a + b + c; }

void main() {
    const auto total = 1
        + 2
        + 3;
    const auto r = sum3(
        10,
        20,
        30
    );
    const auto xs = [
        1,
        2,
        3
    ];
    println(total, r, xs);
}
```

If you forget the `;`, the compiler points at the token where the statement should have ended:

```zark error
void main() {
    const auto total = 1
    println(total);
}
```

Several statements fit on one line:

```zark run
void main() {
    auto x = 1; x += 1; x *= 10;
    println(x);
}
```

`else` can go on the same line as `}` or on the next one:

```zark run
void main() {
    const auto n = 5;
    if (n > 3) {
        println("greater");
    }
    else {
        println("not greater");
    }
}
```

`zark fmt` always writes `} else {` on one line, see [tooling](tooling.md#zark-fmt).

## Identifiers

A name consists of Latin letters, digits and `_`, and does not start with a digit. Case matters. Names that start with two underscores (`__find`, `__qsort`) are used inside the standard library: do not name your own things like that.

Keywords cannot be used as names:

```text
fn const static template struct union enum type import as extern export
if else while for match return break continue defer errdefer
test is orelse catch sizeof alignof true false null nullptr error
```

> **Note:** `auto`, `this` and `Self` are not keywords in the strict sense, but they have a special meaning: `auto` in place of a type, `this` and `Self` inside [methods](structs-unions-enums.md#methods).

## Integer literals

| Form | Value |
|---|---|
| `42` | decimal |
| `0xff` | hexadecimal, 255 |
| `0b101` | binary, 5 |
| `0o17` | octal, 15 |
| `1_000_000` | `_` is a digit separator and does not affect the value |

```zark run
void main() {
    println(42, 0xff, 0b101, 0o17, 1_000_000);
    println(0xDEAD_BEEF, 0b1111_0000);
}
```

The type of an integer literal comes from the context; without a context it is `i64`:

```zark run
void main() {
    const auto a = 7;
    const u8 b = 200;
    const i16 c = -5;
    u32 d = 4000000000;
    println(a, b, c, d);
}
```

A literal must fit into its type, otherwise it is a compile error:

```zark error
void main() {
    const u8 b = 300;
    println(b);
}
```

`u8` is 0..255, `i8` is -128..127. To truncate on purpose, write `as`: `300 as u8` is `44`.

## Floating-point literals

```zark run
void main() {
    println(3.14, 1e9, 2.5e-3, 1_000.5);
    const f32 f = 0.1;
    println(f);
}
```

A literal like `1e9` is floating-point (`f64`) even though it is written without a dot. The default type is `f64`; in an `f32` context the literal becomes `f32`.

## Characters

A character in single quotes is a number of type `u8` (a byte code). Unicode characters outside ASCII do not fit into single quotes: they take several bytes.

```zark run
void main() {
    const auto c = 'A';
    println(c, c + 1, (c + 1) as u8 == 'B');
    println("{c:c} {'z':c}");
    const auto digit = '7' - '0';
    println(digit);
}
```

A number is printed unless you ask for the `:c` format. More about formats in [strings](strings.md#formatting).

## String literals

A string in double quotes has the type `str`: a slice of bytes `{ ptr, len }` (see [types](types.md#str)). The literal lives in the program's memory and ends with a zero byte, so it can be passed to C directly.

### Escape sequences

| Form | Meaning |
|---|---|
| `\n` | newline |
| `\t` | tab |
| `\r` | carriage return |
| `\0` | zero byte |
| `\e` | the ESC character (0x1b), for terminal colors |
| `\\` | backslash |
| `\"` | double quote |
| `\'` | single quote |
| `\{` | a literal `{` |
| `\}` | a literal `}` |

```zark run
void main() {
    println("line 1\nline 2");
    println("column\tcolumn");
    println("quotes: \" and \\");
    println("braces: \{ and \}");
}
```

### Multi-line strings

A string literal can contain a real newline. It goes into the value as it is, together with the indentation:

```zark run
void main() {
    const auto text = "first
second
third";
    println(text);
    println(text.len);
}
```

### Interpolation

In `"..."` an expression in curly braces is evaluated and substituted. The braces are part of the format, so literal ones must be doubled: `{{` and `}}` (or escaped as `\{`).

```zark run
void main() {
    const auto a = 6;
    const auto b = 7;
    println("{a} * {b} = {a * b}");
    println("{{a}} is not a substitution");
    println("{a + b > 10} {a:03}");
}
```

Interpolation is not a function call and allocates nothing on the heap: the compiler turns the string into a format for `printf`. Details are in [strings and formatting](strings.md).

> **Gotcha:** a forgotten `{{` is a common mistake when printing JSON or C code: `"{"key": 1}"` breaks, and you need `"{{\"key\": 1}}"`.

## Booleans and null

`true` and `false` are `bool` values. `null` is "the empty pointer" and "the empty `?T`", described in [errors and optional values](errors-and-optionals.md).

## Precedence and associativity

The operator precedence table is on the [operators](operators.md#precedence) page.
