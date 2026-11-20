---
title: Standard library reference
order: 40
section: Reference
description: All the functions and types of the Vibe prelude: output, strings, numbers, allocators, List, Map, Option, files, processes, time and math
---

The standard library is a single file, `std/std.vibe`, written in Vibe itself. It is attached to every program **automatically** (the prelude). Nothing needs to be imported.

The names from the prelude share a namespace with yours: you cannot declare your own function named `min`, `max`, `abs`, `sort`, `swap`, `run`, `env`, `cstr`, `arg` and so on; you will get the error "duplicate function".

Names with the prefix `__` (`__find`, `__qsort`) are internal. Do not call them.

Signatures are written as in code: the result, the name, the parameters. `!T` means the function can return an error; `a` is a value of type `Allocator`.

## Output and formatting

These are **built-in** functions of the compiler. The format is `println("x = {x}")`; details are on the page [strings](strings.md#formatting).

| Function | What it does |
|---|---|
| `print(...)` | prints the arguments separated by spaces |
| `println(...)` | the same plus a newline |
| `eprint(...)`, `eprintln(...)` | the same to stderr |
| `!str bprint(u8[] buf, ...)` | formats into a buffer; `error.NoSpace` if it does not fit |
| `!void sprint(List<u8>* out, ...)` | appends to a list |
| `panic(msg)` | prints the message and the location, exits with code 1 |
| `assert(cond)` | `panic` with a location if `cond` is false |
| `embed("file")` | the bytes of a file as a `str` constant, read at compile time |
| `sizeof(T)`, `alignof(T)` | the size and alignment of a type, `u64`, at compile time |

## Allocators

```vibe
struct Allocator {
    void* ctx;
    fn(void*, u64, u64) -> void* alloc_fn;
    fn(void*, void*, u64) free_fn;
}
```

| Function | What it does |
|---|---|
| `Allocator c_allocator()` | `calloc` / `free` |
| `!T[] a.alloc<T>(i64 n)` | `n` elements, zeroed; `error.OutOfMemory` |
| `a.free(slice)` | frees a slice from `alloc` |
| `!T* a.create<T>()` | one zeroed `T` |
| `a.destroy(p)` | frees a `create` |
| `!str a.dup(str s)` | a copy of a string |
| `!u8* a.dupz(str s)` | a copy with a zero byte, for C |

### `FixedBuf`

| Function | What it does |
|---|---|
| `FixedBuf FixedBuf::init(u8[] buf)` | an allocator over your buffer |
| `Allocator fb.allocator()` | the allocator itself |
| `fb.reset()` | treats the whole buffer as free |
| `i64 fb.remaining()` | how many bytes are left |

### `Arena`

| Function | What it does |
|---|---|
| `Arena Arena::init(Allocator parent)` | an arena over a parent |
| `Allocator ar.allocator()` | the allocator itself |
| `ar.deinit()` | frees everything at once |

More: [memory](memory.md).

## `List<T>`

| Method | What it does |
|---|---|
| `List<T>::init(a)` | an empty list |
| `deinit()` | frees the buffer |
| `!void reserve(n)` | allocates capacity |
| `!void push(v)` | appends |
| `!void append(T[] xs)` | appends several |
| `!T pop()` | removes the last, `error.Empty` |
| `!T last()` | the last, `error.Empty` |
| `T get(i)` | an element |
| `set(i, v)` | writes |
| `T[] slice()` | the elements as a slice |
| `bool is_empty()` | whether it is empty |
| `clear()` | length to zero |
| `bool contains(v)` | whether it is there |
| `reverse()` | reverses |
| `sort()` | sorts |
| fields `items`, `len`, `a` | the buffer, the number of elements, the allocator |

## `Map<V>`

| Method | What it does |
|---|---|
| `Map<V>::init(a)` | an empty table |
| `deinit()` | frees the memory |
| `!void put(str key, v)` | inserts or replaces |
| `!V get(str key)` | the value, `error.NotFound` |
| `bool has(str key)` | whether the key exists |
| fields `len`, `entries` | the number of keys; records `{ key, value, used }` |

Keys are not copied.

## `Option<T>`

```vibe
union Option<T> {
    T Some;
    None;
}
```

`?T` is the notation for `Option<T>`.

| Method | What it does |
|---|---|
| `bool is_some()` | whether there is a value |
| `T unwrap_or(d)` | the value or `d` |

## Math and general functions

| Function | What it does |
|---|---|
| `min(a, b)`, `max(a, b)` | the smaller, the larger |
| `abs(x)` | the absolute value of a number |
| `void swap(T* a, T* b)` | swaps values |
| `void sort(T[] s)` | sorts in place |
| `sqrt`, `sin`, `cos`, `tan`, `exp`, `log` | `f64 → f64` |
| `pow(x, y)` | a power |
| `floor`, `ceil`, `fabs` | round down, round up, absolute value |
| `PI` | 3.141592653589793 |

```vibe run
void main() {
    println(sqrt(16.0), sin(0.0), cos(0.0), floor(2.7), ceil(2.1), fabs(-3.0));
    println(exp(0.0), log(1.0), pow(2.0, 10.0), PI);
    println(min(3, 4), max(3.5, 1.0), abs(-5));
}
```

## Strings and characters

| Function | What it does |
|---|---|
| `i64 str_find(s, needle)` | the position of a substring, `-1` |
| `i64 str_find_byte(s, c)` | the position of a byte, `-1` |
| `i64 str_rfind_byte(s, c)` | the last position of a byte, `-1` |
| `str_starts_with(s, p)`, `str_ends_with(s, p)` | the start and the end |
| `str str_trim(s)` | strips whitespace from both ends |
| `str cstr(u8* p)` | a C string as a `str` |
| `!u8* to_cstr(buf, s)` | a C string in your buffer, `error.NoSpace` |
| `is_digit`, `is_alpha`, `is_alnum`, `is_upper`, `is_hex` | character classes (`u8`) |

## Numbers from text

| Function | What it does |
|---|---|
| `!i64 parse_int(s)` | an integer, allows a sign and spaces; `error.InvalidNumber` |
| `!u64 parse_int_radix(s, radix)` | in a radix; `radix` 0 autodetects `0x`, `0b`, `0o` |
| `!f64 parse_float(s)` | a float, `error.InvalidNumber` |
| `u64 bits_f64(x)` | the bits of a number |
| `f64 f64_from_bits(x)` | a number from bits |

```vibe run
void main() {
    println(parse_int(" -42 ") catch 0);
    println(parse_int("4x") catch -1);
    println(parse_int_radix("ff", 16) catch 0);
    println(parse_int_radix("0b101", 0) catch 0);
    println(parse_float("2.5e1") catch 0.0);
    println(bits_f64(1.0), f64_from_bits(4611686018427387904));
}
```

## Files

| Function | What it does |
|---|---|
| `!str read_file(a, path)` | the whole file into memory; `error.FileNotFound`, `error.ReadFailed` |
| `!void write_file(path, data)` | writes, replacing; `error.CannotOpen`, `error.WriteFailed` |
| `bool file_exists(path)` | whether it exists |
| `i32 remove(u8* path)` | deletes (a C function) |
| `i32 mkdir(u8* path, u32 mode)` | creates a directory (a C function) |

The result of `read_file` is allocated through `a`: free it (or use an arena).

```vibe run
!void main() {
    const auto a = c_allocator();
    write_file("demo.txt", "line 1\nline 2\n")?;
    println(file_exists("demo.txt"));

    const auto text = read_file(a, "demo.txt")?;
    defer a.free(text);
    println(text.len);

    const auto missing = read_file(a, "no-such-file.txt") catch |e| {
        println("no file: {e}");
        return;
    };
    println(missing.len);
}
```

## Input

| Function | What it does |
|---|---|
| `!str read_line(u8[] buf)` | one line from stdin without `\n`; `error.EndOfFile` |

## Processes and environment

| Function | What it does |
|---|---|
| `!i32 run(a, str[] argv)` | starts a process, waits, returns the exit code; `error.Signaled` if killed by a signal |
| `!str env(name)` | an environment variable; `error.NotFound` |
| `i64 arg_count()` | the number of arguments (including the program name) |
| `str arg(i)` | an argument by number; `arg(0)` is the program path |
| `void exit(i32 code)` | ends the program |

```vibe run
!void main() {
    const auto a = c_allocator();
    const auto code = run(a, ["/bin/echo", "hi", "there"])?;
    println("code", code);
    const auto bad = run(a, ["/bin/sh", "-c", "exit 3"])?;
    println("code", bad);
    println(env("NO_SUCH_VAR_HERE") catch "not set");
    println(arg_count());
}
```

Program arguments with `vibe run` go after `--`: `vibe run main.vibe -- a b`.

## Time and random numbers

| Function | What it does |
|---|---|
| `i64 now_ns()` | monotonic time in nanoseconds (for measuring) |
| `i64 clock()` | processor time (a C function) |
| `i64 time(null)` | Unix seconds (a C function) |
| `i32 rand()`, `srand(u32 seed)` | the C generator |

Measuring time:

```vibe run
void main() {
    const auto t0 = now_ns();
    auto s = 0;
    for (auto i : 0..1000000) { s += i; }
    const auto ms = (now_ns() - t0) as f64 / 1000000.0;
    println(s, ms >= 0.0);
}
```

## libc functions available without a declaration

From the C library the prelude already declares: `printf`, `malloc`, `calloc`, `free`, `exit`, `memcmp`, `memcpy`, `memmove`, `memset`, `strlen`, `fdopen`, `fgets`, `fopen`, `fclose`, `fread`, `fwrite`, `fseek`, `ftell`, `remove`, `mkdir`, `fork`, `execvp`, `waitpid`, `getenv`, `fflush`, `strtod`, `clock_gettime`, `clock`, `rand`, `srand`, `time` and math. Call any other one through `extern` (see [C](c-interop.md)).

## What next

- End-to-end examples with these functions: [cookbook](cookbook.md).
- If something does not work as expected: [pitfalls and FAQ](gotchas.md).
