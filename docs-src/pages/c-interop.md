---
title: Interoperating with C and C++
order: 30
section: Interop and tools
description: import of C headers, zark cbind, extern, export, strings and pointers at the boundary with C, bringing in .c, .cpp and libraries, build flags and zark.toml keys, structs, callbacks and the extern "C" facade in Zark
---

Zark needs no separate "binding layer": a C header is imported like a module, a single C function can be declared in one line, and a C file is passed to the compiler on the command line. This page collects everything you need at the boundary.

## Importing a C header

`import "x.h" as name;` reads a C header and makes its declarations available under `name::`. Without `as`, they land in the importing file's scope.

```c file=shapes.h
#define SHAPES_MAX 8

typedef struct { float x, y; } Vec2;
typedef enum { SHAPE_CIRCLE, SHAPE_BOX } ShapeKind;

typedef struct {
    ShapeKind kind;
    Vec2 pos;
    float size;
} Shape;

float shape_area(const Shape *s);
Vec2 vec2_add(Vec2 a, Vec2 b);

static inline float sq(float x) { return x * x; }
```

```c file=shapes.c
#include "shapes.h"

float shape_area(const Shape *s) {
    return s->kind == SHAPE_CIRCLE ? 3.0f * sq(s->size) : sq(s->size);
}

Vec2 vec2_add(Vec2 a, Vec2 b) { Vec2 r = { a.x + b.x, a.y + b.y }; return r; }
```

```zark run with=shapes.c
import "shapes.h" as sh;

void main() {
    auto s = sh::Shape{ .kind = sh::SHAPE_BOX, .size = 3.0 };
    s.pos = sh::vec2_add(sh::Vec2{ .x = 1.0, .y = 2.0 }, sh::Vec2{ .x = 0.5, .y = 0.5 });
    println(sh::shape_area(&s), s.pos.x, s.pos.y, sh::SHAPES_MAX, sh::sq(4.0));
}
```

What you get:

- functions become `extern` declarations, structs become Zark structs with the same layout, `typedef` becomes `type`;
- an `enum` becomes an integer type plus one constant per value; a `#define` of a number, a string or a character becomes a constant;
- a union becomes a struct with raw storage and one accessor per member: `*u.as_d() = 2.5;`;
- a `static inline` function gets a small C wrapper that the compiler builds and links for you;
- an `extern` variable becomes a function `name_ptr()` that returns its address, a struct with bitfields gets `get_f()` and `set_f(v)` for each bitfield, and a struct aligned above 8 becomes an `align(N) struct` (see [variables, bitfields and alignment](#c-variables-bitfields-and-alignment));
- a field or parameter named like a Zark keyword gets a trailing `_` (`type` becomes `type_`).

The header is looked up next to the importing file, then in the `-I` directories, then in the system include path, and it sees the same `-D` and `-I` flags as the C sources. The result is cached in `.zark-cache/cbind/` and rebuilt when the header, anything it includes, the flags, the clang version or the Zark compiler change.

Some C constructs have no Zark equivalent yet and are skipped: `long double`, `_Complex`, `_Atomic`, `__int128`, SIMD vector types, function-like macros, thread-local, `static` and `volatile` variables, bitfields inside unions, and structs passed by value through function pointer types. `import` skips them silently; `zark cbind` lists them.

## Seeing the bindings: `zark cbind`

`zark cbind` prints what an import would produce, plus one warning per skipped declaration:

```sh
zark cbind shapes.h                          # Zark declarations to stdout, warnings to stderr
zark cbind gl.h -DGL_GLEXT_PROTOTYPES -o gl.zk
zark cbind shapes.h -o shapes.zk --inline-c shapes_inline.c
```

The output is a plain `.zk` file you can read and edit. With `--inline-c` the wrappers for `static inline` functions go to a C file that you compile in next to it (`zark run main.zk shapes_inline.c`). That C file includes the header by its absolute path, and the wrapper names in both files are hashed from that path, so the pair only works on the machine and in the checkout where it was made. Use it to inspect what an import produces, and let `import` regenerate the bindings elsewhere. A header without `static inline` functions produces a `.zk` that does not depend on the path.

Only C headers work. A C++ library is reached through a C API, as cimgui does for Dear ImGui (`examples/imgui/`), or through your own `extern "C"` facade (see below).



## Calling C from Zark: `extern`

`extern` declares a function that lives outside. The signature is written in Zark terms, and the correspondence with C is simple:

| C | Zark |
|---|---|
| `int`, `int32_t` | `i32` |
| `long`, `int64_t`, `ssize_t` | `i64` |
| `unsigned`, `uint32_t` | `u32` |
| `size_t`, `uint64_t` | `u64` |
| `char` | `i8` where `char` is signed (x86-64, Apple arm64), `u8` where it is unsigned (Linux arm64) |
| `signed char`, `int8_t` / `unsigned char`, `uint8_t` | `i8` / `u8` |
| `double` / `float` | `f64` / `f32` |
| `char *`, `const char *` | `u8*` |
| `void *` | `void*` |
| any `T *` | `T*` |
| `void` (a result) | no result is written |
| `...` | `...` |

```zark run
extern i32 puts(u8* s);
extern i32 atoi(u8* s);
extern u64 strlen(u8* s);

void main() {
    puts("hello from C");
    println(atoi("41") + 1, strlen("abcd"));
}
```

The libc functions that are often needed are already declared in the prelude (`printf`, `malloc`, `calloc`, `free`, `exit`, `memcpy`, `memset`, `strlen`, `sqrt`, `sin`, `cos`, `pow`, `floor`, `fopen`, `fork` and so on). You can simply call them, and declaring them again is not required.

> **Gotcha:** if you declare an `extern` with a name that is already taken by a **Zark function** from the prelude (`abs`, `min`, `max`, `sort`), you get the error "duplicate function". Choose another approach, or import the C version into a wrapper with a different name.

## Strings at the boundary

A literal `"..."` always ends with a zero byte, so it fits as a `u8*` (that is, a `const char *`):

```zark run
extern i32 puts(u8* s);

void main() {
    puts("a literal: it can be passed as it is");
}
```

Any other `str` (a slice) does not end with anything and is **not suitable** as a C string. The type `str` is `{ ptr, len }`, and only `s.ptr` goes to C, which is read up to a zero byte:

```zark run
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

```zark run
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

```zark run
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

Any Zark pointer converts to `void*` and back **implicitly**; to other pointer types, through `as`:

```zark run
void main() {
    i64 x = 258;
    const auto p = &x as *u8;
    println(p[0], p[1]);
}
```

An array or a slice becomes a pointer to the first element through `.ptr` (for slices) or `&a[0]`/`as T*`:

```zark run
extern void* memset(void* dst, i32 c, u64 n);

void main() {
    u8[8] buf;
    memset(buf[..].ptr as *void, 65, 4);
    println(buf);
}
```

## Variable number of arguments

`...` in an `extern` allows variadic functions. The types are promoted by the usual C rules: integers are widened, `f32` → `f64`. Structs and unions among the variable arguments travel as C passes them. Slices and arrays are not allowed, and a variadic function cannot be used as a `fn` value, so it is only called directly.

```zark run
extern i32 printf(u8* fmt, ...);

void main() {
    printf("%d %s %.2f\n", 5, "str", 2.5);
}
```

For output from Zark itself, `println` is better: it is safer. `printf` is handy when working with ready-made C code.

## Structs

Zark structs lie in memory the same way as C structs (the same sizes and alignment). So the description on the Zark side is a copy of the description in C.

Structs can be passed to `extern` functions and returned from them **by value**, as in C: on x86-64 the compiler follows the System V rules (small structs travel in registers, larger ones on the stack or through a hidden pointer) on every backend, and on arm64 (Linux and Apple) the AAPCS64 rules, which only the LLVM path implements; there is no native backend for arm64, so every arm64 build goes through LLVM. The same holds for `export` functions and for function pointers in both directions. This is what libraries like raylib need: `extern void DrawCircleV(Vector2 center, f32 radius, Color color);` works as written. Passing by pointer works as well:

```zark file=vec.c
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

```zark run with=vec.c
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

By value:

```zark file=v2.c
typedef struct { float x, y; } Vector2;
typedef struct { unsigned char r, g, b, a; } Color;

Vector2 v2_add(Vector2 a, Vector2 b) { Vector2 r = { a.x + b.x, a.y + b.y }; return r; }
Color fade(Color c, float k) { Color o = { c.r, c.g, c.b, (unsigned char)(c.a * k) }; return o; }
```

```zark run with=v2.c
struct Vector2 { f32 x; f32 y; }
struct Color { u8 r; u8 g; u8 b; u8 a; }

extern Vector2 v2_add(Vector2 a, Vector2 b);
extern Color fade(Color c, f32 k);

void main() {
    println(v2_add(Vector2{ .x = 1.0, .y = 2.0 }, Vector2{ .x = 3.0, .y = 4.0 }));
    println(fade(Color{ .r = 255, .g = 128, .b = 0, .a = 200 }, 0.5));
}
```

A Zark `union` crosses the boundary by value too. C sees it as `struct { int32_t tag; _Alignas(8) union { ... } payload; }`, and the tag is the zero-based index of the variant in declaration order:

```c file=shape.c
#include <stdint.h>

typedef struct { double w, h; } Box;
typedef struct {
    int32_t tag;
    _Alignas(8) union { double r; Box box; } u;
} Shape;

double area(Shape s) { return s.tag == 0 ? 3.0 * s.u.r * s.u.r : s.u.box.w * s.u.box.h; }
Shape unit_box(void) { Shape s = { .tag = 1, .u.box = { 1.0, 1.0 } }; return s; }
```

```zark run with=shape.c
struct Box { f64 w; f64 h; }
union Shape { f64 Circle; Box Rect; }

extern f64 area(Shape s);
extern Shape unit_box();

void main() {
    println(area(Shape::Circle(2.0)), area(Shape::Rect(Box{ .w = 2.0, .h = 5.0 })));
    println(unit_box() is .Rect);
}
```

SIMD vectors pass as the C vector type of the same size (`f32x4` is `float __attribute__((vector_size(16)))`): 16-byte vectors on every target and 8-byte ones on arm64. Other sizes, and vectors inside a struct or union passed by value, are rejected at compile time.

## C variables, bitfields and alignment

An `extern` variable of a header becomes `name_ptr()`, which returns its address, so reads and writes go straight to the C variable. A struct with bitfields becomes opaque storage of the same size with `get_f()` and `set_f(v)` for each named bitfield; C does the masking and sign extension. A struct aligned above 8 (`__attribute__((aligned(16)))`, an `_Alignas` member) becomes an `align(N) struct` with the same layout:

```c file=dev.h
extern int dev_count;
extern const char *dev_name;

struct flags {
    unsigned ready : 1;
    unsigned mode : 3;
    int level : 4;
};

typedef struct __attribute__((aligned(16))) { float x, y, z, w; } Vec4;

int dev_tick(int by);
float vec4_sum(Vec4 v);
```

```c file=dev.c
#include "dev.h"

int dev_count = 41;
const char *dev_name = "lamp";

int dev_tick(int by) { dev_count += by; return dev_count; }
float vec4_sum(Vec4 v) { return v.x + v.y + v.z + v.w; }
```

```zark run with=dev.c
import "dev.h" as dev;

void main() {
    *dev::dev_count_ptr() += 1;
    println(*dev::dev_count_ptr(), dev::dev_tick(8), cstr(*dev::dev_name_ptr()));

    dev::flags f;
    f.set_ready(1);
    f.set_mode(5);
    f.set_level(-3);
    println(f.get_ready(), f.get_mode(), f.get_level(), sizeof(dev::flags));

    const auto v = dev::Vec4{ .x = 1.0, .y = 2.0, .z = 3.0, .w = 4.0 };
    println(alignof(dev::Vec4), dev::vec4_sum(v));
}
```

The accessor of a variable is linked only when the program calls its `name_ptr()`, so a declared variable the program never touches need not exist. A plain `char` follows the signedness of the target: `i8` on x86-64 and Apple arm64, `u8` on Linux arm64 (and with `-funsigned-char`); pass the same `-fsigned-char`/`-funsigned-char` to `zark cbind` and to the C files.

## Bringing in C files

`zark run`, `zark build` and `zark test` accept `.c`, `.cpp`, `.o`, `.a`, `.so` and the options `-l...` / `-L...` together with the source:

```sh
zark run main.zk mathlib.c                 # compiles mathlib.c and links
zark run main.zk mathlib.c engine.cpp      # with C++ the link goes through clang++
zark build main.zk lib.o -lm -o app        # a ready object and a library
```

What happens: every `.c` / `.cpp` is compiled with `clang` (`clang++` for C++, the optimization level comes from `-O`), then everything is linked together with your program. If there is at least one `.cpp`, the linker becomes `clang++`.

Compile flags on the same command line go to every C/C++ file and to imported headers: `-I…`, `-D…`, `-U…`, `-std=…`, `-f…`, `-W…`, `-pthread`. A C standard is used for `.c` files and headers, a C++ standard only for C++ files:

```sh
zark run main.zk lib.c engine.cpp -Ivendor/include -DUSE_FAST=1 -std=c++17
```

Objects are cached in `.zark-cache/obj/` by the compiler, flags and source text, and rebuilt when a header they include changes. Several files compile in parallel (up to 8; `ZARK_JOBS=N` sets the number).

A Zark file without `main` can be linked with a C `main`, and a program made only of C or C++ files works too.

## Projects with C code

In a project, `zark.toml` holds the same settings. This is the manifest of `examples/imgui/`, which builds Dear ImGui from source and talks to it and to SDL2 through `import`:

```text
[package]
name = "imgui-demo"
main = "main.zk"

[build]
include = ["deps/cimgui", "deps/cimgui/imgui", "deps/cimgui/imgui/backends"]
defines = ["CIMGUI_USE_SDL2", "CIMGUI_USE_OPENGL3", "IMGUI_IMPL_API=extern \"C\""]
std = "c++17"
cflags = ["-fno-exceptions", "-fno-rtti"]
sources = ["deps/cimgui/cimgui.cpp", "deps/cimgui/imgui/imgui.cpp", "..."]
pkg-config = ["sdl2"]
libs = ["GL", "stdc++"]
```

| Key | What it does |
|---|---|
| `sources` | C/C++ files to compile and link |
| `libs` | libraries, `-lNAME` |
| `lib-dirs` | `-L` directories |
| `include` | `-I` directories |
| `defines` | `-D` macros, `"NAME"` or `"NAME=VALUE"` |
| `std` | `-std=` for C or C++ |
| `cflags` | any other compile flags |
| `pkg-config` | packages whose `pkg-config --cflags --libs` is added |

Paths are relative to `zark.toml`. More about manifests is in [projects](projects.md).

Details of the modes are in [tooling](tooling.md#compilation-modes).

## Calling Zark from C: `export`

`export` exposes a Zark function under its own name. C code sees it as an ordinary external symbol:

```zark file=sumsq.c
#include <stdint.h>

extern int64_t zark_square(int64_t x);

int64_t c_sum_squares(int64_t n) {
    int64_t s = 0;
    for (int64_t i = 1; i <= n; i++) s += zark_square(i);
    return s;
}
```

```zark run with=sumsq.c
extern i64 c_sum_squares(i64 n);

export i64 zark_square(i64 x) {
    return x * x;
}

void main() {
    println(c_sum_squares(10));
}
```

The names of `extern` and `export` are C symbols, so they **get no module prefix**, even with `import ... as` (see [modules](modules.md)).

## Callbacks: function pointers

A Zark function can be passed to C as `fn(...) -> R`. This is a plain function address without a closure:

```zark run
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

Zark does not know the C++ ABI (templates, overloads, classes). So C++ is hidden behind a small C interface where an object is an opaque pointer.

```zark file=engine.cpp
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

```zark run with=engine.cpp
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
zark run main.zk -lm
zark run main.zk -L/opt/foo/lib -lfoo
zark build main.zk libbar.a -o app
```

Math (`sqrt`, `sin`, `pow`) is linked automatically: `-lm` is already included.

## Rules and pitfalls

- A hand-written `extern` is a place for mistakes: its types must match C. Prefer `import "x.h"` when there is a header.
- Structs and unions cross the boundary by value through `extern`, `export` and function pointers. `import` still skips C function pointer types with a struct passed by value; declare such a type by hand if you need it.
- Two headers imported without `as` cannot both include the same header: import the one header that includes both. With `as`, each import has its own copy of the shared types, and they are different Zark types (convert pointers with `as`).
- `bool` in C is `_Bool`/`uint8_t`. Use `u8` or `i32`, not `bool`, if in doubt.
- Do not pass a `str` instead of a `u8*`: you need `s.ptr` (and a zero byte, see above).
- `size_t` is `u64`, `ssize_t` is `i64`.
- Memory returned by a C function (`malloc`) must be freed by a C function (`free`), not by a Zark allocator.
- An `extern` with the same name as a function from the Zark prelude is not allowed.

## What next

- Files and processes: [reference](stdlib.md).
- Build modes and flags: [tooling](tooling.md).
