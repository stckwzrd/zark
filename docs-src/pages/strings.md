---
title: Strings and formatting
order: 18
section: Language
description: The str type, slices and comparing strings, interpolation, format specifiers, print, bprint, sprint and text functions
---

## What `str` is

`str` is a slice of bytes: a pointer to the data and a length (`{ ptr, len }`, 16 bytes). It is the same as `u8[]`. All the behavior follows from that:

- A string **does not own** memory. A literal `"..."` lives in the program's memory, and copying a `str` copies only the pointer and the length.
- A string does not have to end with a zero (but a literal does, see [C](c-interop.md)).
- The length is `s.len`, a byte is `s[i]`, a substring is `s[a..b]`.
- These are **bytes**, not characters. A letter like `é` takes 2 bytes.

```zark run
void main() {
    const auto s = "hello";
    println(s.len, s[0], s[1..4], s[..2], s[3..]);
    const auto ru = "héllo";
    println(ru.len, ru[1], ru[2]);
}
```

`s[0]` is a number of type `u8`. To print it as a character, use the `:c` format (see below).

### Strings are immutable

The contents of a literal cannot be changed. An attempt to write into it crashes the program, because the memory of literals is write-protected:

```zark run exit
void main() {
    auto s = "abc";
    s[0] = 65;
}
```

To get a mutable string, copy it into your own buffer:

```zark run
void main() {
    u8[3] buf = [97, 98, 99];
    const str s = buf[..];
    buf[0] = 90;
    println(s);
}
```

## Comparison

`==` and `!=` compare the **contents** (with `memcmp` inside). There is no ordering (`<`).

```zark run
void main() {
    const auto a = "abc";
    const auto b = "ab";
    println(a == "abc", a != b, a == "ABC");
    println("" == "");
}
```

There is no `+` for strings: joining is done by formatting into a buffer (see below).

## Interpolation

In a string literal, `{expression}` is evaluated and inserted. Any expression is allowed, including calls, indexing, arithmetic, comparisons and casts.

```zark run
i64 double(i64 x) { return x * 2; }

void main() {
    const auto a = 6;
    const auto name = "world";
    const auto xs = [10, 20, 30];
    println("hello, {name}");
    println("{a} * 2 = {double(a)}");
    println("sum {xs[0] + xs[1]}, length {xs.len}");
    println("slice {xs[1..]}");
    println("{a > 3 && a < 9}, {a as f64 / 4.0}");
}
```

Literal curly braces are `{{` and `}}` (or `\{` and `\}`):

```zark run
void main() {
    const auto v = 3;
    println("{{\"v\": {v}}}");
    println("set {{1, 2}}");
}
```

**Important:** interpolation is **not** allocating a string. The compiler expands it into a format for `printf`, and the values are printed right away, with nothing allocated on the heap. So `"..{x}.."` without a print function call **does not create a value of type `str`**. Interpolation is allowed only in the arguments of a function whose last parameter has the type `Fmt`: that is `print`, `println`, `eprint`, `eprintln`, `panic`, `bprint`, `sprint` and your own (see [Your own print functions](#your-own-print-functions)):

```zark error fragment
const auto n = 5;
const auto s = "n = {n}";
println(s);
```

If you need a string value, build it in a buffer: `bprint` or `sprint` (see [Building strings](#building-strings)).

## Printing

| Function | What it does |
|---|---|
| `print(...)` | to stdout, without a newline |
| `println(...)` | to stdout, with a newline |
| `eprint(...)` | to stderr, without a newline |
| `eprintln(...)` | to stderr, with a newline |

Arguments can be listed with commas: they are printed separated by spaces. **Any** type can be printed:

```zark run
struct P { i64 x; f64 y; }
enum Color { Red, Green }
union U { i64 A; B; }

void main() {
    const auto p = P{ .x = 1, .y = 2.5 };
    println(1, "two", 3.5, true, 'x');
    println(p, [1, 2, 3], "string");
    println(Color::Green, U::A(7), U::B);
    println(&p == &p);
    print("no newline, ");
    print("continued\n");
    eprintln("this goes to stderr");
}
```

How types are printed:

| Type | Form |
|---|---|
| integers | a decimal number |
| `f32`, `f64` | like `%g`: up to 6 significant digits |
| `bool` | `true` / `false` |
| `str` | the text; inside structs and arrays, in quotes |
| `'a'` | a number (the byte code) |
| pointer | the address, like `%p` |
| enum | `.Name` |
| error | `error.Name` |
| struct | `Name{ field: value }` |
| union | `Name.Variant(payload)` |
| array, slice | `[a, b, c]` |

## Formatting

After an expression you can put `:` and a specification, as in `printf`: flags, width, precision, a type letter.

```text
{expression : [flags][width][.precision][type]}
```

### Integers

| Form | Result for 255 | Meaning |
|---|---|---|
| `{n}` | `255` | decimal |
| `{n:x}` | `ff` | hexadecimal, lowercase |
| `{n:X}` | `FF` | hexadecimal, uppercase |
| `{n:08X}` | `000000FF` | width 8, leading zeros |
| `{n:6}` | `   255` | width 6, right-aligned |
| `{n:-6}` | `255   ` | width 6, left-aligned |
| `{n:06}` | `000255` | zeros in front |
| `{n:+}` | `+255` | always with a sign |
| `{c:c}` | `A` for 65 | the number as a character |

```zark run
void main() {
    const auto n = 255;
    println("[{n}] [{n:x}] [{n:X}] [{n:08X}]");
    println("[{n:6}] [{n:-6}] [{n:06}] [{n:+}]");
    println("[{65:c}] [{'z':c}]");
    const u8 h = 7;
    println("{h:02x}");
}
```

There is no binary printing: `{n:b}` prints `<bad format>`. For a binary form, take the number apart bit by bit by hand.

### Floating-point

| Form | For 3.14159265 | Meaning |
|---|---|---|
| `{f}` | `3.14159` | `%g` |
| `{f:.2}` | `3.14` | two digits after the point |
| `{f:8.3}` | `   3.142` | width 8, three digits |
| `{f:-8.1}` | `3.1     ` | left-aligned |
| `{f:e}` | `3.141593e+00` | exponential notation |

```zark run
void main() {
    const auto f = 3.14159265;
    println("[{f}] [{f:.2}] [{f:8.3}] [{f:-8.1}] [{f:e}]");
    println(1.0 / 3.0, 100000.0, 1000000.0, 1e-5, 2.0);
}
```

Note that `100000.0` is printed as `100000`, and `1000000.0` as `1e+06`. For a constant form, use a precision: `{x:.1}`.

### Strings

Width works with strings too:

```zark run
void main() {
    const auto name = "hi";
    println("[{name:6}] [{name:-6}]");
    println("{name:-10}|");
}
```

A precision on a string truncates it: `{s:.3}` prints the first three bytes. For a substring in code, use the slice `s[0..3]`.

Width is counted in bytes, so non-ASCII text is aligned imprecisely.

## Building strings

Need a string value? There are two ways.

### `bprint`: into your own buffer

`bprint(buf, ...)` formats into your array and returns a `!str`, a slice of that buffer. If it does not fit, you get `error.NoSpace`. Nothing is allocated.

```zark run
!void main() {
    u8[32] buf;
    const auto s = bprint(buf[..], "x = {1 + 2}, y = {2.5:.1}")?;
    println(s, s.len);

    u8[4] tiny;
    const auto r = bprint(tiny[..], "a string that is too long") catch |e| {
        println("did not fit: {e}");
        "?";
    };
    println(r);
}
```

The result lives exactly as long as the buffer.

### `sprint`: into a growing list

`sprint(&list, ...)` appends text to a `List<u8>`. It grows through the list's allocator. Ideal for building in pieces:

```zark run
!void main() {
    auto out = List<u8>::init(c_allocator());
    defer out.deinit();
    for (auto i : 0..4) {
        sprint(&out, "{i}")?;
        if (i < 3) { sprint(&out, ", ")?; }
    }
    sprint(&out, " end")?;
    const auto s = out.slice();
    println(s, s.len);
}
```

`out.slice()` is a `u8[]`, and it can be passed as a `str`.

## Your own print functions

If the last parameter of a function is `Fmt`, then the string with `{...}` and all the other arguments of the call are gathered into it. You can pass the `Fmt` on to `print` or `println` as it is:

```zark run
void note(str tag, Fmt f) {
    print("[{tag}] ");
    println(f);
}

void main() {
    note("info", "x = {1 + 2}, y = {2.5:.1}");
    note("warn", "no values");
}
```

## Standard library functions

| Function | What it does |
|---|---|
| `i64 str_find(s, needle)` | the position of a substring, or `-1` |
| `i64 str_find_byte(s, c)` | the first position of a byte, or `-1` |
| `i64 str_rfind_byte(s, c)` | the last position of a byte, or `-1` |
| `bool str_starts_with(s, p)` | starts with |
| `bool str_ends_with(s, p)` | ends with |
| `str str_trim(s)` | strip whitespace from both ends |
| `!i64 parse_int(s)` | a number from a string (surrounding spaces are allowed) |
| `!u64 parse_int_radix(s, r)` | a number in a radix (0 means autodetect `0x`, `0b`, `0o`) |
| `!f64 parse_float(s)` | a floating-point number |
| `is_digit`, `is_alpha`, `is_alnum`, `is_upper`, `is_hex` | character classes (`u8`) |
| `!str a.dup(s)` | a copy on the heap |
| `str cstr(p)` | a `str` from a C string |
| `!u8* to_cstr(buf, s)` | a C string in your buffer |
| `!u8* a.dupz(s)` | a C string on the heap |

```zark run
!void main() {
    const auto s = "  Hello, Zark!  ";
    const auto t = str_trim(s);
    println("[{t}]");
    println(str_find(t, "Zark"), str_find(t, "nope"), str_find_byte(t, ','), str_rfind_byte(t, 'l'));
    println(str_starts_with(t, "Hello"), str_ends_with(t, "!"));
    println(t[0..5], t[7..]);
    println(parse_int("42") catch -1, parse_int("12x") catch -1);
    println(parse_float("2.5") catch 0.0);
    println(parse_int_radix("ff", 16) catch 0, parse_int_radix("0x1f", 0) catch 0);
    println(is_digit('5'), is_alpha('x'), is_alnum('_'), is_upper('A'), is_hex('f'));
}
```

The prelude has `str_split`, `str_join`, `str_replace`, `str_to_upper` and more (see [the reference](stdlib.md#more-strings)). The recipes below show how such functions are written by hand.

### Splitting by a separator

```zark run
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    const auto csv = "a,b,,c";
    auto parts = List<str>::init(a);
    auto start = 0;
    for (auto [i, c] : csv) {
        if (c == ',') {
            parts.push(csv[start..i])?;
            start = i + 1;
        }
    }
    parts.push(csv[start..])?;
    println(parts.slice(), parts.len);
}
```

The parts are slices of the original string; nothing is copied.

### Changing case

Changing needs your own memory:

```zark run
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    const auto src = "Hello, Zark!";
    const auto up = a.alloc<u8>(src.len)?;
    for (auto [i, c] : src) {
        if (c >= 'a' && c <= 'z') {
            up[i] = c - 32;
        } else {
            up[i] = c;
        }
    }
    println(up);
}
```

## Input

`read_line(buf)` reads a line from stdin (without the newline) or returns `error.EndOfFile`:

```zark run with=allow-fail
void main() {
    u8[128] buf;
    const auto line = read_line(buf[..]) catch {
        println("no input");
        return;
    };
    println("read: {line}");
}
```

To read a whole file: `read_file(a, path)`; to write: `write_file(path, data)`. More in the [reference](stdlib.md).

## `embed`: a file as a string constant

`embed("path")` reads a file at compile time and puts its bytes into the program as a `str`. The path is relative to the source file.

```text
const auto banner = embed("banner.txt");
println(banner);
```

This is handy for templates, help texts and small resources: the program stays a single file.

## What next

- Where to keep built strings: [memory and allocators](memory.md).
- `List` and `Map`: [collections](collections.md).
- Strings in C: [interoperating with C](c-interop.md).
