---
title: Interoperating with C and C++
order: 30
section: Interop and tools
description: extern, export, strings and pointers at the boundary with C, bringing in .c, .cpp and libraries, structs, callbacks and the extern "C" facade in Vibe
---

Vibe needs no separate "binding layer": a C function is declared in one line, and a C file is passed to the compiler on the command line. This page collects everything you need at the boundary.

## Calling C from Vibe: `extern`

`extern` declares a function that lives outside. The signature is written in Vibe terms, and the correspondence with C is simple:

| C | Vibe |
|---|---|
| `int`, `int32_t` | `i32` |
| `long`, `int64_t`, `ssize_t` | `i64` |
| `unsigned`, `uint32_t` | `u32` |
| `size_t`, `uint64_t` | `u64` |
| `char`, `uint8_t` | `u8` |
| `double` / `float` | `f64` / `f32` |
| `char *`, `const char *` | `u8*` |
| `void *` | `void*` |
| any `T *` | `T*` |
| `void` (a result) | no result is written |
| `...` | `...` |

```vibe run
extern i32 puts(u8* s);
extern i32 atoi(u8* s);
extern u64 strlen(u8* s);

void main() {
    puts("hello from C");
    println(atoi("41") + 1, strlen("abcd"));
}
```

The libc functions that are often needed are already declared in the prelude (`printf`, `malloc`, `calloc`, `free`, `exit`, `memcpy`, `memset`, `strlen`, `sqrt`, `sin`, `cos`, `pow`, `floor`, `fopen`, `fork` and so on). You can simply call them, and declaring them again is not required.

> **Gotcha:** if you declare an `extern` with a name that is already taken by a **Vibe function** from the prelude (`abs`, `min`, `max`, `sort`), you get the error "duplicate function". Choose another approach, or import the C version into a wrapper with a different name.

## Strings at the boundary

A literal `"..."` always ends with a zero byte, so it fits as a `u8*` (that is, a `const char *`):

```vibe run
extern i32 puts(u8* s);

void main() {
    puts("a literal: it can be passed as it is");
}
```

Any other `str` (a slice) does not end with anything and is **not suitable** as a C string. The type `str` is `{ ptr, len }`, and only `s.ptr` goes to C, which is read up to a zero byte:

```vibe run
extern i32 puts(u8* s);

void main() {
    const auto name = "abc";
    const auto part = name[0..2];
    puts(part.ptr);
}
```

You expected `ab` and got `abc`: after `ab` there is no zero byte, and C reads on. For such strings you need a C string. There are two ways:

- `to_cstr(buf, s)` copies into **your** buffer and adds a zero byte (no memory allocation);
- `a.dupz(s)` copies onto the heap through an allocator.

```vibe run
extern i32 puts(u8* s);

!void main() {
    const auto name = "abcdef";
    const auto part = name[0..3];

    u8[16] buf;
    const auto c1 = to_cstr(buf[..], part)?;
    puts(c1);

    const auto a = c_allocator();
    const auto c2 = a.dupz(part)?;
    defer a.free(c2[0..part.len + 1]);
    puts(c2);
}
```

The other way: `cstr(p)` turns a C string `u8*` into a `str` (the length is computed with `strlen`, nothing is copied):

```vibe run
extern u8* getenv(u8* name);

void main() {
    const auto p = getenv("PATH");
    if (p != null) {
        const auto s = cstr(p);
        println(s.len > 0);
    }
    const auto q = getenv("THIS_IS_NOT_SET");
    println(q == null);
}
```

## Pointers

Any Vibe pointer converts to `void*` and back **implicitly**; to other pointer types, through `as`:

```vibe run
void main() {
    i64 x = 258;
    const auto p = &x as *u8;
    println(p[0], p[1]);
}
```

An array or a slice becomes a pointer to the first element through `.ptr` (for slices) or `&a[0]`/`as T*`:

```vibe run
extern void* memset(void* dst, i32 c, u64 n);

void main() {
    u8[8] buf;
    memset(buf[..].ptr as *void, 65, 4);
    println(buf);
}
```

## Variable number of arguments

`...` in an `extern` allows variadic functions. The types are promoted by the usual C rules: integers are widened, `f32` → `f64`. Slices are not allowed.

```vibe run
extern i32 printf(u8* fmt, ...);

void main() {
    printf("%d %s %.2f\n", 5, "str", 2.5);
}
```

For output from Vibe itself, `println` is better: it is safer. `printf` is handy when working with ready-made C code.

## Structs

Vibe structs lie in memory the same way as C structs (the same sizes and alignment). So the description on the Vibe side is a copy of the description in C.

**Structs are passed to C by pointer only.** Passing and returning by value is not supported yet.

```vibe file=vec.c
typedef struct { double x, y, z; } Vec3;

double vec3_dot(const Vec3 *a, const Vec3 *b) {
    return a->x * b->x + a->y * b->y + a->z * b->z;
}

void vec3_scale(Vec3 *v, double k) {
    v->x *= k;
    v->y *= k;
    v->z *= k;
}
```

```vibe run with=vec.c
struct Vec3 { f64 x; f64 y; f64 z; }

extern f64 vec3_dot(Vec3* a, Vec3* b);
extern void vec3_scale(Vec3* v, f64 k);

void main() {
    auto a = Vec3{ .x = 1.0, .y = 2.0, .z = 3.0 };
    auto b = Vec3{ .x = 4.0, .y = 5.0, .z = 6.0 };
    println(vec3_dot(&a, &b));
    vec3_scale(&a, 10.0);
    println(a);
}
```

## Bringing in C files

`vibe run`, `vibe build` and `vibe test` accept `.c`, `.cpp`, `.o`, `.a`, `.so` and the options `-l...` / `-L...` together with the source:

```sh
vibe run main.vibe mathlib.c                 # compiles mathlib.c and links
vibe run main.vibe mathlib.c engine.cpp      # with C++ the link goes through clang++
vibe build main.vibe lib.o -lm -o app        # a ready object and a library
```

What happens: every `.c` / `.cpp` is compiled with `clang` (`clang++` for C++, the optimization level comes from `-O`), then everything is linked together with your program. If there is at least one `.cpp`, the linker becomes `clang++`.

Details of the modes are in [tooling](tooling.md#compilation-modes).

## Calling Vibe from C: `export`

`export` exposes a Vibe function under its own name. C code sees it as an ordinary external symbol:

```vibe file=sumsq.c
#include <stdint.h>

extern int64_t vibe_square(int64_t x);

int64_t c_sum_squares(int64_t n) {
    int64_t s = 0;
    for (int64_t i = 1; i <= n; i++) s += vibe_square(i);
    return s;
}
```

```vibe run with=sumsq.c
extern i64 c_sum_squares(i64 n);

export i64 vibe_square(i64 x) {
    return x * x;
}

void main() {
    println(c_sum_squares(10));
}
```

The names of `extern` and `export` are C symbols, so they **get no module prefix**, even with `import ... as` (see [modules](modules.md)).

## Callbacks: function pointers

A Vibe function can be passed to C as `fn(...) -> R`. This is a plain function address without a closure:

```vibe run
extern void qsort(void* base, u64 n, u64 size, fn(void*, void*) -> i32 cmp);

i32 cmp(void* a, void* b) {
    const auto x = *(a as *i64);
    const auto y = *(b as *i64);
    if (x < y) { return -1; }
    if (x > y) { return 1; }
    return 0;
}

void main() {
    auto xs = [5, 3, 9, 1, 7];
    qsort(xs[..] as *void, 5, 8, cmp);
    println(xs);
}
```

A closure `fn[](...) -> R` cannot be passed to C: it has a context, and C expects a plain address.

## C++ through an `extern "C"` facade

Vibe does not know the C++ ABI (templates, overloads, classes). So C++ is hidden behind a small C interface where an object is an opaque pointer.

```vibe file=engine.cpp
#include <vector>
#include <algorithm>
#include <cstdint>

struct Engine { std::vector<double> v; };

extern "C" {
    void *engine_new() { return new Engine; }
    void engine_push(void *e, double x) { static_cast<Engine *>(e)->v.push_back(x); }
    double engine_median(void *e) {
        auto &v = static_cast<Engine *>(e)->v;
        std::sort(v.begin(), v.end());
        return v.empty() ? 0 : v[v.size() / 2];
    }
    void engine_free(void *e) { delete static_cast<Engine *>(e); }
}
```

```vibe run with=engine.cpp
extern void* engine_new();
extern void engine_push(void* e, f64 x);
extern f64 engine_median(void* e);
extern void engine_free(void* e);

void main() {
    const auto e = engine_new();
    defer engine_free(e);
    for (auto x : [5.0, 1.0, 9.0, 3.0, 7.0]) {
        engine_push(e, x);
    }
    println(engine_median(e));
}
```

`defer` here guarantees `engine_free` on any exit.

## Libraries: `-l` and `-L`

Bringing in system libraries works as in C. The options `-l` and `-L` and the files `.a`, `.so`, `.o` are passed to the linker as they are:

```sh
vibe run main.vibe -lm
vibe run main.vibe -L/opt/foo/lib -lfoo
vibe build main.vibe libbar.a -o app
```

Math (`sqrt`, `sin`, `pow`) is linked automatically: `-lm` is already included.

## Rules and pitfalls

- There is no `@cImport` and no header parsing: you write the signatures by hand. This is a place for mistakes: the type of your `extern` must match C.
- Structs do not cross the boundary by value.
- `bool` in C is `_Bool`/`uint8_t`. Use `u8` or `i32`, not `bool`, if in doubt.
- Do not pass a `str` instead of a `u8*`: you need `s.ptr` (and a zero byte, see above).
- `size_t` is `u64`, `ssize_t` is `i64`.
- Memory returned by a C function (`malloc`) must be freed by a C function (`free`), not by a Vibe allocator.
- An `extern` with the same name as a function from the Vibe prelude is not allowed.

## What next

- Files and processes: [reference](stdlib.md).
- Build modes and flags: [tooling](tooling.md).
