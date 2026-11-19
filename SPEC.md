# Vibe language spec (v0.4)

This file is the contract for the self-hosted compiler: anything written here must behave the same in both compilers.

## 0. Design rules

1. **No hidden allocations.** No language construct and no prelude function touches the heap on its own. Memory is taken only through an `Allocator` that you pass explicitly. String interpolation is a compile-time format string handed to `printf`/`snprintf`.
2. **No hidden control flow.** The only implicit things are `defer`/`errdefer` (written next to the code they affect), bounds checks (removed with `--release`), and `==` on `str` (an inline `memcmp`).
3. **One way to do each thing.** `let`/`var` for bindings, `?` to propagate errors, `catch` to handle them, `match` to branch on enums and unions.
4. **Conversions are visible.** Implicit conversions are limited to lossless int widening, `T` → `!T`, `error.X` → `!T`, `null` → pointer/fn, and `*T` ↔ `*void`. Everything else is `as`.
5. **What you see is the layout.** Structs are laid out like C structs. A union is `{ i32 tag, payload }`. `str` is `{ *u8, i64 }`.

## 1. Lexical

- Comments: `// ...` and `/* ... */`.
- A newline ends a statement when the line ends with an identifier, a literal, `)`, `]`, `}`, `?`, `return`, `break`, `continue`, `true`, `false` or `null`. Inside `(` and `[` newlines are ignored. `;` can also be written explicitly.
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
| `*T` | pointer, supports arithmetic `p + n` and `p[i]` | `ptr` |
| `*void` | opaque "any pointer", converts to and from every `*T` | `ptr` |
| `[]T` | slice `{ptr, len}`, bounds-checked | `{ptr, i64}` |
| `str` | the same as `[]u8` | `{ptr, i64}` |
| `[N]T` | fixed array, `N` is a compile-time constant | `[N x T]` |
| `!T` | error union | `{i32, T}` |
| `fn(A, B) R` | function pointer (`R` may be omitted for void) | `ptr` |
| `struct S[T..]` | product type | named struct |
| `union U[T..]` | tagged union | `{i32, [n x i64]}` |
| `enum E` | plain tag | `i32` |

Integer literals take their type from context and default to `i64`. Float literals default to `f64`.

## 3. Declarations

```vibe
import "path.vibe"                   // relative to the current file, loaded once
import "net.vibe" as net             // namespaced: net.connect(...), net.Conn{ ... }
type Bytes = []u8                    // type alias (any type expression)
const N = 4 * 2                      // compile-time constant (inlined)
var counter: i64 = 0                 // global variable, constant initializer
struct P[T] { x: T, y: T }
union Shape { Circle: f64, Rect: P[f64], Empty }
enum Color { Red, Green }
fn name[T](a: T, b: i64) !T { ... }  // generic, monomorphized on use
fn sort[T: Ord](s: []T) { ... }      // constrained generic, checked at the call
extern fn puts(s: *u8) i32           // C symbol
extern fn printf(fmt: *u8, ...) i32  // C varargs
export fn cb(x: i64) i64 { ... }     // emitted under its C name
impl P[T] {
    fn new(x: T, y: T) Self { ... }  // static: P[i64].new(1, 2)
    fn len(self) T { ... }           // `self` alone means `self: *Self`
    fn by_value(self: Self) T { ... }
}
```

Only reachable functions are compiled. Generic code is type-checked when it is instantiated; constraints (`Eq`, `Ord`, `Num`, `Int`, `Float`) are checked at the call or at the type instantiation, before the body is compiled.

### Modules

`import "file.vibe" as name` loads the file once and gives every declaration in it (functions, structs, unions, enums, constants, globals, type aliases) the prefix `name.`. Inside the file its own names keep working unprefixed. `extern` and `export` names stay global. Rules, all checked by the compiler:

- A file is imported under one name for the whole program, and a name belongs to one file.
- A plain `import "file.vibe"` still puts everything in the global namespace.
- The alias is reserved in the importing file: `net.x` always means the module member.

### Tests

`test "name" { ... }` at the top level declares a test: a function returning `!void`. `vibe test file.vibe` runs the tests of that file, each in its own process, and prints the output of the failed ones. `assert` and `?` fail a test. Tests are ignored by `run` and `build`.

## 4. Statements

`let x = e`, `let x: T = e`, `var x = e`, `var x: T` (zeroed); `x = e` and `x op= e`; `_ = e` discards a value; `if c {} else if d {} else {}`; `while c {}`; `for i in a..b {}` (half-open); `for x in seq {}` and `for i, x in seq {}` over arrays, slices and anything with `slice()`; `break`, `continue`, `return [e]`; `defer stmt`, `errdefer stmt`; `match`.

`let` forbids reassigning the binding and changing it through fields or array elements. Data reached through a pointer or slice can still be changed.

## 5. Expressions

Precedence, lowest to highest:

`catch` < `||` < `&&` < `== != < <= > >=` < `|` < `^` < `&` < `<< >>` < `+ -` < `* / %` < `as` < unary `- ! ~ & *` < postfix `() [] [a..b] .f ?`

`as` is weaker than prefix operators, as in Rust: `&x as *T` means `(&x) as *T`, and `-a as i64` means `(-a) as i64`.

- `T{ f: e, ... }` lists every field. Write `T{ f: e, .. }` to zero the rest, or `T{ .. }` for an all-zero value.
- `[a, b, c]` gives an array `[3]T`. With an expected `[]T` it becomes a slice over stack storage.
- `x[a..b]`, `x[a..]`, `x[..b]`, `x[..]` slice arrays, slices and pointers. Pointers need an end index.
- `e as T` covers int↔int, int↔float, float↔float, ptr↔ptr, ptr↔int, enum↔int and `[]T` → `*T`.
- `sizeof(T)` and `alignof(T)` are compile-time `u64` values.
- `match v { pat => expr, ... }` is also an expression. Arms are expressions or blocks whose last statement is the value, or leave with `return`/`break`/`continue`. All values are converted to one type (the expected type, otherwise the first arm's). An expression `match` must be exhaustive: cover every variant or add `_`.
- `?T` means `Option[T]`. `null` and a plain `T` convert to `?T` implicitly; `.Some(x)` and `.None` also work. `a orelse b` yields the value of `a`, or `b` when it is empty; `b` can also be `return`, `break` or `continue`.
- `fn[a, b](x: i64) i64 { ... }` is a closure. The listed variables are captured by reference: the closure keeps pointers to them in a context on the stack of the function that wrote the literal, so it must not outlive that function. Its type is `fn[](i64) i64`. A closure is called like a function and costs one indirect call.
- `.Name` is an enum value or payload-less union variant, typed by context. `.Name(e)` is a union variant with a payload, also typed by context.
- `Type.Variant` and `Type.Variant(e)` are the explicit forms.
- `x is .Variant` (or `x is Type.Variant`) is a `bool` test of an enum value or union tag.

### Errors

```vibe
fn f() !i64 { if bad { return error.Bad } return 1 }
let a = f()?                           // on error: run errdefers + defers, return the error
let b = f() catch 0                    // default value
let c = f() catch |e| { log(e); -1 }   // a block whose last expression is the value
f() catch |e| { return e }             // or leave
```

Ignoring an error union is a compile error. `errdefer` runs on every error return, whether the error is `return error.X`, `?`, or a `return g()` that turns out to be an error at runtime. When `main` returns `!void`, an unhandled error prints `error: Name` and exits with code 1.

### match

```vibe
match v {
    1, 2 => stmt                  // ints, enums, str: equality
    .Circle(r) => { ... }         // unions: binds the payload (read-only)
    .Empty => {}
    _ => {}                       // anything else
}
```

Arms are tested top to bottom, there is no fall-through, and a `match` is not required to be exhaustive.

## 6. Builtins

| Builtin | Notes |
|---|---|
| `print(...)`, `println(...)`, `eprint(...)`, `eprintln(...)` | arguments are joined by spaces; any type is formatted |
| `embed("file")` | the file's bytes as a `str` constant, path relative to the source file (read at compile time) |
| `bprint(buf: []u8, ...) !str` | formats into `buf`; `error.NoSpace` if it does not fit |
| `sprint(out: *List[u8], ...) !void` | appends formatted text; growth goes through the list's own allocator |
| `panic(msg)` | prints the message with file:line, exits 1 |
| `assert(cond)` | panics with file:line |

Format specs: `{v:x}` `{v:08X}` `{v:5}` `{v:-10}` (str padding) `{v:.3}` `{v:e}` `{c:c}`. These are printf flags, width and precision, followed by an optional conversion letter.

Formatting: ints in decimal, floats with `%g`, `bool` as true/false, `str` as text, pointers as `%p`, enums as `.Name`, errors as `error.Name`, structs as `S{ f: v }`, unions as `U.V(payload)`, arrays and slices as `[a, b]`.

## 7. Memory

```vibe
struct Allocator {
    ctx: *void
    alloc_fn: fn(*void, u64, u64) *void   // (ctx, size, align) -> zeroed memory or null
    free_fn: fn(*void, *void, u64)        // (ctx, ptr, size)
}
a.alloc[T](n) ![]T    a.free(slice)    a.create[T]() !*T    a.destroy(p)    a.dup(s) !str
```

The prelude provides two allocators:
- `c_allocator()` uses `calloc`/`free`.
- `FixedBuf.init(buf).allocator()` is a bump allocator over memory you own. It never uses the heap and has `reset()` and `remaining()`.
- `Arena.init(parent).allocator()` is a growable bump allocator. Its chunks come from `parent`, and `deinit()` releases everything at once.

You can write your own allocator by filling in the two function pointers.

Containers such as `List[T]` and `Map[V]` take the allocator in `init` and release memory in `deinit`. Every growing operation returns `!void`, so running out of memory is an ordinary error you handle.

## 8. C interop

- `extern fn` declares a C function and `export fn` defines one.
- `*void` is `void*`. String literals pass as `*u8` (they are NUL-terminated). Any other `str` must be passed as `s.ptr` explicitly.
- C varargs follow the usual promotions; slices are rejected.
- Structs are passed by pointer. By-value passing is not supported yet.
- `vibe run main.vibe x.c y.cpp lib.o -lfoo` compiles and links everything, using `clang++` if C++ is present.

## 9. System (prelude)

| Area | Functions |
|---|---|
| Files | `read_file(a, path) !str`, `write_file(path, data) !void`, `file_exists(path)` |
| Processes | `run(a, argv: []str) !i32` (fork/execvp/waitpid; returns the exit code), `env(name) !str`, `arg_count()`, `arg(i)` |
| C strings | `to_cstr(buf, s) !*u8` (no allocation), `a.dupz(s) !*u8`, `cstr(p) str` |
| Numbers | `parse_int`, `parse_int_radix(s, radix) !u64` (radix 0 = auto 0x/0b/0o), `parse_float`, `bits_f64`, `f64_from_bits` |
| Strings | `str_find`, `str_find_byte`, `str_rfind_byte`, `str_trim`, `str_starts_with`, `str_ends_with`, `is_digit/is_alpha/is_alnum/is_hex/is_upper` |

## 10. Not in v0.3 (deliberately)

Heap-allocated closures, operator overloading, exceptions, a GC, implicit copies through a heap, inheritance, and macros.

Candidates for later: `comptime` blocks, `inline for`, and `@cImport`.
