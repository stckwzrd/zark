# Vibe language spec (v0.4)

This file is the contract for the self-hosted compiler: anything written here must behave the same in both compilers.

## 0. Design rules

1. **No hidden allocations.** No language construct and no prelude function touches the heap on its own. Memory is taken only through an `Allocator` that you pass explicitly. String interpolation is a compile-time format string handed to `printf`/`snprintf`.
2. **No hidden control flow.** The only implicit things are `defer`/`errdefer` (written next to the code they affect), bounds checks (removed with `--release`), and `==` on `str` (an inline `memcmp`).
3. **One way to do each thing.** `auto`/`const` for bindings, `?` to propagate errors, `catch` to handle them, `match` to branch on enums and unions.
4. **Conversions are visible.** Implicit conversions are limited to lossless int widening, `T` → `!T`, `error.X` → `!T`, `null` → pointer/fn, and `T*` ↔ `void*`. Everything else is `as`.
5. **What you see is the layout.** Structs are laid out like C structs. A union is `{ i32 tag, payload }`. `str` is `{ u8*, i64 }`.

## Syntax overview

The syntax follows C++: type-first declarations (`i64 x = 1;`, `auto`, `const`), `template<T>` for generic functions, `struct Pair<A, B>` for generic types, methods declared inside the `struct` (or out of class as `R Type::name()`), `[&k](T x) -> R {}` for closures, `for (T x : seq)`, `::` and `->` as aliases of `.`, `nullptr` as `null`, and `++ -- |= &= ^= <<= >>=`. Every statement ends with `;`. See the guide page `cpp-style`.

## 1. Lexical

- Comments: `// ...` and `/* ... */`.
- A statement ends with `;`. It is not written after the `}` that closes a block, a function, a `struct`, an `enum`, a `union`, an `if`, a `while`, a `for` or a `match`. Newlines mean nothing.
- `} else` may go on the next line.
- Literals: `42`, `0xff`, `0b101`, `0o17`, `1_000`, `3.14`, `1e9`, `'a'` (a `u8`), `"text"`, `true`, `false`, `null`.
- Escapes: `\n \t \r \0 \e \\ \" \' \{ \}`.
- Interpolation: `"x = {expr}"`; `{{` and `}}` produce literal braces.

## 2. Types

| Type | Meaning | LLVM |
|---|---|---|
| `i8 i16 i32 i64 isize` | signed ints | `iN` |
| `u8 u16 u32 u64 usize` | unsigned ints | `iN` |
| `f32 f64` | floats | `float`/`double` |
| `bool` | | `i1` |
| `void` | | |
| `T*` | pointer, supports arithmetic `p + n` and `p[i]` | `ptr` |
| `void*` | opaque "any pointer", converts to and from every `T*` | `ptr` |
| `T[]` | slice `{ptr, len}`, bounds-checked | `{ptr, i64}` |
| `str` | the same as `u8[]` | `{ptr, i64}` |
| `T[N]` | fixed array, `N` is a compile-time constant | `[N x T]` |
| `!T` | error union | `{i32, T}` |
| `fn(A, B) -> R` | function pointer | `ptr` |
| `struct S<T..>` | product type | named struct |
| `union U<T..>` | tagged union | `{i32, [n x i64]}` |
| `enum E` | plain tag | `i32` |

Integer literals take their type from context and default to `i64`. Float literals default to `f64`.

## 3. Declarations

```vibe
import "path.vibe";                    // relative to the current file, loaded once
import "net.vibe" as net;              // namespaced: net::connect(...), net::Conn{ ... }
type Bytes = u8[];                     // type alias (any type expression)
const auto N = 4 * 2;                  // compile-time constant (inlined)
i64 counter = 0;                       // global variable, constant initializer
struct P<T> {
    T x;
    T y;
    static Self make(T x, T y) { ... }  // static: P<i64>::make(1, 2)
    T len() { ... }                     // `this` is a pointer to the object
}
union Shape { f64 Circle; P<f64> Rect; Empty; }
enum Color { Red, Green }
template<T> !T name(T a, i64 b) { ... }       // generic, monomorphized on use
template<T: Ord> void sort(T[] s) { ... }     // constrained generic, checked at the call
extern i32 puts(u8* s);                // C symbol
extern i32 printf(u8* fmt, ...);       // C varargs
export i64 cb(i64 x) { ... }           // emitted under its C name
```

Only reachable functions are compiled. Generic code is type-checked when it is instantiated; constraints (`Eq`, `Ord`, `Num`, `Int`, `Float`) are checked at the call or at the type instantiation, before the body is compiled.

### Modules

`import "file.vibe" as name;` loads the file once and gives every declaration in it (functions, structs, unions, enums, constants, globals, type aliases) the prefix `name::`. Inside the file its own names keep working unprefixed. An `extern` gets the prefix too but links to the same C symbol; `export` names stay global. Rules, all checked by the compiler:

- A file is loaded once; it may be imported under several names, which all refer to it. A name belongs to one file, and a file imported with a name somewhere cannot also be imported plainly.
- A plain `import "file.vibe"` still puts everything in the global namespace.
- The alias is reserved in the importing file: `net::x` always means the module member.

### Tests

`test "name" { ... }` at the top level declares a test: a function returning `!void`. `vibe test file.vibe` runs the tests of that file, each in its own process, and prints the output of the failed ones. `assert` and `?` fail a test. Tests are ignored by `run` and `build`.

## 4. Statements

`T x = e;`, `auto x = e;`, `const T x = e;`, `T x;` (zeroed); `x = e;` and `x op= e;`; `x++;` and `x--;`; `_ = e;` discards a value; `if (c) {} else if (d) {} else {}`; `while (c) {}`; `for (auto i : a..b) {}` (half-open); `for (auto x : seq) {}` and `for (auto [i, x] : seq) {}` over arrays, slices and anything with `slice()`; `break`, `continue` (`name: for ...` labels a loop, `break name;` and `continue name;` leave or continue that loop), `return [e]`; `defer stmt`, `errdefer stmt`; `match`.

`const` forbids reassigning the variable and changing it through fields or array elements. Data reached through a pointer or slice can still be changed. Variables and parameters are mutable by default; a parameter is a copy.

## 5. Expressions

Precedence, lowest to highest:

`catch` < `||` < `&&` < `== != < <= > >=` < `|` < `^` < `&` < `<< >>` < `+ -` < `* / %` < `as` < unary `- ! ~ & *` < postfix `() [] [a..b] .f ?`

`as` is weaker than prefix operators: `&x as *T` means `(&x) as *T`, and `-a as i64` means `(-a) as i64`.

- `T{ .f = e, ... }` sets the listed fields and zeroes the rest; `T{}` is an all-zero value.
- `[a, b, c]` gives an array `T[3]`. With an expected `T[]` it becomes a slice over stack storage.
- `x[a..b]`, `x[a..]`, `x[..b]`, `x[..]` slice arrays, slices and pointers. Pointers need an end index.
- `e as T` covers int↔int, int↔float, float↔float, ptr↔ptr, ptr↔int, enum↔int and `T[]` → `T*`.
- `sizeof(T)` and `alignof(T)` are compile-time `u64` values.
- `match v { pat => expr, ... }` is also an expression. Arms are expressions or blocks whose last statement is the value, or leave with `return`/`break`/`continue`. All values are converted to one type (the expected type, otherwise the first arm's). An expression `match` must be exhaustive: cover every variant or add `_`.
- `?T` means `Option<T>`. `null` and a plain `T` convert to `?T` implicitly; `.Some(x)` and `.None` also work. `a orelse b` yields the value of `a`, or `b` when it is empty; `b` can also be `return`, `break` or `continue`.
- `[&a, &b](i64 x) -> i64 { ... }` is a closure. The listed variables are captured by reference: the closure keeps pointers to them in a context on the stack of the function that wrote the literal, so it must not outlive that function. Its type is `fn[](i64) -> i64`. A closure is called like a function and costs one indirect call.
- `.Name` is an enum value or payload-less union variant, typed by context. `.Name(e)` is a union variant with a payload, also typed by context.
- `Type::Variant` and `Type::Variant(e)` are the explicit forms.
- `x is .Variant` (or `x is Type::Variant`) is a `bool` test of an enum value or union tag.

### Errors

```vibe
!i64 f() { if (bad) { return error.Bad; } return 1; }
auto a = f()?;                          // on error: run errdefers + defers, return the error
auto b = f() catch 0;                   // default value
auto c = f() catch |e| { log(e); -1 };  // a block whose last expression is the value
f() catch |e| { return e; }             // or leave
```

Ignoring an error union is a compile error. `errdefer` runs on every error return, whether the error is `return error.X`, `?`, or a `return g()` that turns out to be an error at runtime. When `main` returns `!void`, an unhandled error prints `error: Name` and exits with code 1.

### match

```vibe
match v {
    1, 2 => stmt;                  // ints, enums, str: equality
    .Circle(r) => { ... }          // unions: binds the payload (read-only)
    .Empty => {}
    _ => {}                        // anything else
}
```

Arms are tested top to bottom, there is no fall-through, and a `match` is not required to be exhaustive.

## 6. Builtins and formatting

The compiler itself knows only these names: `sizeof`, `alignof`, `embed`, `panic`, `assert`, the type `Fmt`, `Self`, `error`, `Option` (the meaning of `?T`) and the runtime helpers `__panic`, `__oob`, `__ovf`, `__str_eq`, `__errname`, `__rt_init` (called first by `main` and by the test runner unless `--freestanding`; the prelude uses it to install the crash handler). Everything else is ordinary code in `std/std.vibe`.

| Builtin | Notes |
|---|---|
| `embed("file")` | the file's bytes as a `str` constant, path relative to the source file (read at compile time) |
| `panic(...)` | prints `panic: ` and the formatted arguments with file:line, exits 1; lowers to `__panic` |
| `assert(cond)` | prints `assertion failed (file:line)`, exits 1 |

### `Fmt`

A call whose callee has a last parameter of type `Fmt` receives **all remaining arguments** as one `Fmt` value: a string literal is parsed for `{expr}` / `{expr:spec}` holes, every other expression becomes one hole, and the pieces are joined by single spaces. A `Fmt` lives on the stack of the caller (no heap, no `printf`); it is only built at call sites. An interpolated string anywhere else is a compile error. If the only remaining argument already is a `Fmt`, it is passed through.

The std defines, in plain Vibe: `print`, `println`, `eprint`, `eprintln`, `!str bprint(u8[] buf, Fmt f)` (`error.NoSpace` if it does not fit, one byte is kept for a NUL), `!void sprint(List<u8>* out, Fmt f)`, and `Writer { ctx, write_fn }`. Your own functions can take a `Fmt` too. Arguments are evaluated before the fixed arguments of the same call.

Each hole is formatted by a generated thunk that calls the std hooks `__fmt_int`, `__fmt_uint`, `__fmt_float`, `__fmt_bool`, `__fmt_str`, `__fmt_ptr`, `__fmt_lit`. A struct, union or enum that has a method `!void fmt(Writer* w, str spec)` is formatted by it; otherwise the compiler derives the output below.

Format specs: `{v:x}` `{v:08X}` `{v:5}` `{v:-10}` `{v:+}` `{v:.3}` (string precision truncates) `{v:e}` `{c:c}`: flags `-+ 0#`, width, `.precision`, then an optional conversion letter. A spec that does not fit the type prints `<bad format>` at run time.

Formatting: ints in decimal, floats with `%g` (through libc `snprintf`), `bool` as true/false, `str` as text (quoted inside aggregates), pointers as `0x...` (`(nil)` for null), enums as `.Name`, errors as `error.Name`, structs as `S{ f: v }`, unions as `U.V(payload)` (`U.V` when nested), arrays as `[a, b]` (at most 32 elements), slices as `[a, b]` (`[]T(len=N)` when nested), `void` as `void`.

## 6a. Types with behavior

- Default field values: `i64 n = 5;` in a struct applies to `T{}`, `T{ .x = 1 }` and `T x;` (also for nested structs).
- Constructors: a method named like the struct without a result type; `T(args)` zero-fills with the defaults, then runs it with `this`. No allocation.
- Interfaces: `interface I { R m(A a); }` declares a two-word struct `{ void* data; IVtable* vt; }` with dispatching methods. `Shape s = &obj;` converts any struct pointer whose type has all the methods (checked structurally). A call is one indirect call. There is no inheritance of implementation.
- Operators on structs: methods `operator+ - * / % == != < <= > >=` and unary `operator-()`; `!=` falls back to `==`. `[]`, `()`, `->`, `<<` and assignment cannot be overloaded.
- `const` after a method's parameters forbids assigning fields and calling non-const methods through `this`.

## 6b. Low-level code

- `volatile T`: a type qualifier for pointees, fields and variables (`volatile u32* p`, `volatile u32 ctrl;`). Every access through such an lvalue is emitted as a volatile load or store of the exact width of `T`. Type equality ignores `volatile`.
- `packed struct` and `packed union`: fields without padding, alignment 1.
- `align(N) T name = v;` before a global variable aligns it to `N` bytes (a power of two, page tables and DMA buffers). Struct types and locals keep their natural alignment.
- `asm<R>("template", "constraints", args...)` (`R` defaults to `void`): LLVM inline asm with `sideeffect`. Braces in the strings are written `\{` and `\}`. The native backend encodes the templates used by the prelude (`Cpu`, `Port`, `Atomic`) and rejects others with a message; `--llvm` accepts any.
- `a +% b`, `a -% b`, `a *% b` are integer operators that always wrap (same precedence as `+` `-` and `*`); they are never checked by `--check-overflow` and never get `nsw` under `--fast`.
- `--check-overflow` makes `+`, `-` and `*` on integers in user code panic on overflow (`__ovf`); without it they wrap.
- `--fast` is `--release` with `nsw` on signed `+ - *`; signed overflow is then undefined. Array and slice indexing is always emitted with `inbounds`.
- `--freestanding` links with `-nostdlib -static`, disables bounds checks, and accepts `-Wl,...`, `-T...`, `.S`, `.c`, `.o` arguments. An `export` function with a body replaces an `extern` declaration of the same name (for `memset`, `memcpy`).
- Prelude: `Cpu`, `Port`, `Bits`, `Atomic`, `Spinlock`.

## 7. Memory

```vibe
struct Allocator {
    void* ctx;
    fn(void*, u64, u64) -> void* alloc_fn;   // (ctx, size, align) -> zeroed memory or null
    fn(void*, void*, u64) free_fn;        // (ctx, ptr, size)
}
!T[] a.alloc<T>(i64 n)    void a.free(T[] slice)    !T* a.create<T>()    void a.destroy(T* p)    !str a.dup(str s)
```

The prelude provides two allocators:
- `c_allocator()` uses `calloc`/`free`.
- `FixedBuf::init(buf).allocator()` is a bump allocator over memory you own. It never uses the heap and has `reset()` and `remaining()`.
- `Arena::init(parent).allocator()` is a growable bump allocator. Its chunks come from `parent`, and `deinit()` releases everything at once.

You can write your own allocator by filling in the two function pointers.

Containers such as `List<T>` and `Map<V>` take the allocator in `init` and release memory in `deinit`. Every growing operation returns `!void`, so running out of memory is an ordinary error you handle.

## 8. C interop

- `extern` declares a C function and `export` defines one.
- `void*` is C's `void*`. String literals pass as `u8*` (they are NUL-terminated). Any other `str` must be passed as `s.ptr` explicitly.
- C varargs follow the usual promotions; slices are rejected.
- Structs are passed by pointer. By-value passing is not supported yet.
- `vibe run main.vibe x.c y.cpp lib.o -lfoo` compiles and links everything, using `clang++` if C++ is present.

## 9. System (prelude)

| Area | Functions |
|---|---|
| Files | `read_file(a, path) !str`, `write_file(path, data) !void`, `file_exists(path)` |
| Processes | `!i32 run(a, str[] argv)` (fork/execvp/waitpid; returns the exit code), `env(name) !str`, `arg_count()`, `arg(i)` |
| C strings | `!u8* to_cstr(buf, s)` (no allocation), `!u8* a.dupz(s)`, `cstr(p) str` |
| Numbers | `parse_int`, `parse_int_radix(s, radix) !u64` (radix 0 = auto 0x/0b/0o), `parse_float`, `bits_f64`, `f64_from_bits` |
| Strings | `str_find`, `str_find_byte`, `str_rfind_byte`, `str_trim`, `str_starts_with`, `str_ends_with`, `is_digit/is_alpha/is_alnum/is_hex/is_upper` |

## 10. Not in v0.3 (deliberately)

Heap-allocated closures, operator overloading, exceptions, a GC, implicit copies through a heap, inheritance, and macros.

Candidates for later: `comptime` blocks, `inline for`, and `@cImport`.
