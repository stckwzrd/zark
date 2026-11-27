# Zark language spec (v0.6, pre-release)

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
- `type` is contextual: it starts an alias declaration only as `type Name = ...;`. Everywhere else (`i64 type;`, `s.type`, `f(i64 type)`) it is an ordinary name.
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

```zark
import "path.zk";                    // relative to the current file, loaded once
import "net.zk" as net;              // namespaced: net::connect(...), net::Conn{ ... }
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
template<T: Ord> void sort(T[] s) { ... }     // constrained: body checked at the declaration
extern i32 puts(u8* s);                // C symbol
extern i32 printf(u8* fmt, ...);       // C varargs
export i64 cb(i64 x) { ... }           // emitted under its C name
```

Only reachable functions are compiled. The body of a generic is checked at its declaration against the declared constraints (`Eq`, `Ord`, `Num`, `Int`, `Float`); a generic without a constraint is checked when it is instantiated. A call whose type does not satisfy the constraint is reported at the call.

### Modules

`import "file.zk" as name;` loads the file once and gives every declaration in it (functions, structs, unions, enums, constants, globals, type aliases) the prefix `name::`. Inside the file its own names keep working unprefixed. An `extern` gets the prefix too but links to the same C symbol; `export` names stay global. Rules, all checked by the compiler:

- A file is loaded once; it may be imported under several names, which all refer to it. A name belongs to one file, and a file imported with a name somewhere cannot also be imported plainly.
- A plain `import "file.zk"` still puts everything in the global namespace.
- The alias is reserved in the importing file: `net::x` always means the module member.

### Tests

`test "name" { ... }` at the top level declares a test: a function returning `!void`. `zark test file.zk` runs the tests of that file, each in its own process, and prints the output of the failed ones. `assert` and `?` fail a test. Tests are ignored by `run` and `build`.

## 4. Statements

`T x = e;`, `auto x = e;`, `const T x = e;`, `T x;` (the zero value of `T`: `0`, `false`, `null`, or an all-zero struct, array or slice); `x = e;` and `x op= e;`; `x++;` and `x--;`; `_ = e;` discards a value; `if (c) {} else if (d) {} else {}`; `while (c) {}`; `for (auto i : a..b) {}` (half-open); `for (auto x : seq) {}` and `for (auto [i, x] : seq) {}` over arrays, slices and anything with `slice()`; `break`, `continue` (`name: for ...` labels a loop, `break name;` and `continue name;` leave or continue that loop), `return [e]`; `defer stmt`, `errdefer stmt`; `match`.

`const` forbids reassigning the variable and changing it through fields or array elements. Data reached through a pointer or slice can still be changed. Variables and parameters are mutable by default; a parameter is a copy.

## 5. Expressions

Precedence, lowest to highest:

`catch` < `||` < `&&` < `== != < <= > >=` < `|` < `^` < `&` < `<< >>` < `+ -` < `* / %` < `as` < unary `- ! ~ & *` < postfix `() [] [a..b] .f ?`

`as` is weaker than prefix operators: `&x as *T` means `(&x) as *T`, and `-a as i64` means `(-a) as i64`.

After `as` the compiler reads a type, with the postfix `*`, `[]` and `[N]` of C++-style types: `p as Node*` and `p as *Node` are the same cast. A `*` straight after a type is part of it only when the next token cannot start an expression (`p as Node*;`, `f(p as Node*)`), so `i as f64 * k` stays a multiplication. For `<`, a name that does not start with an uppercase letter is a type, not the start of type arguments, so `n as i64 < lim` is a comparison. Type arguments accept `!T`, `?T`, pointers and nested generics (`List<Box<!i64>>`); the closing `>>` is split into two `>`.

- `T{ .f = e, ... }` sets the listed fields and zeroes the rest; `T{}` is an all-zero value.
- `[a, b, c]` gives an array `T[3]`. With an expected `T[]` it becomes a slice over stack storage.
- `x[a..b]`, `x[a..]`, `x[..b]`, `x[..]` slice arrays, slices and pointers. Pointers need an end index.
- `e as T` covers int↔int, int↔float, float↔float, ptr↔ptr, ptr↔int, enum↔int and `T[]` → `T*`.
- `sizeof(T)` and `alignof(T)` are compile-time `u64` values. The operand may also be an expression (`sizeof(x)`, `sizeof(f())`); it is not evaluated.
- `match v { pat => expr, ... }` is also an expression. Arms are expressions or blocks whose last statement is the value, or leave with `return`/`break`/`continue`. All values are converted to one type (the expected type, otherwise the first arm's). A `match` on an enum, a union or `bool`, statement or expression, must be exhaustive: cover every variant (both values for `bool`) or add `_ => {}`. A `match` expression on any other type also needs a `_` arm; a `match` statement on an integer, string or pointer may fall through to the next statement.
- `?T` means `Option<T>`. `null` and a plain `T` convert to `?T` implicitly; `.Some(x)` and `.None` also work. `a orelse b` yields the value of `a`, or `b` when it is empty; `b` can also be `return`, `break` or `continue`.
- `[&a, &b](i64 x) -> i64 { ... }` is a closure. The listed variables are captured by reference: the closure keeps pointers to them in a context on the stack of the function that wrote the literal, so it must not outlive that function. Its type is `fn[](i64) -> i64`. A closure is called like a function and costs one indirect call.
- `.Name` is an enum value or payload-less union variant, typed by context. `.Name(e)` is a union variant with a payload, also typed by context.
- `Type::Variant` and `Type::Variant(e)` are the explicit forms.
- `x is .Variant` (or `x is Type::Variant`) is a `bool` test of an enum value or union tag.

### Errors

```zark
!i64 f() { if (bad) { return error.Bad; } return 1; }
auto a = f()?;                          // on error: run errdefers + defers, return the error
auto b = f() catch 0;                   // default value
auto c = f() catch |e| { log(e); -1 };  // a block whose last expression is the value
f() catch |e| { return e; }             // or leave
```

Ignoring an error union is a compile error. `errdefer` runs on every error return, whether the error is `return error.X`, `?`, or a `return g()` that turns out to be an error at runtime. When `main` returns `!void`, an unhandled error prints `error: Name` and exits with code 1.

### match

```zark
match v {
    1, 2 => stmt;                  // ints, enums, str: equality
    .Circle(r) => { ... }          // unions: binds the payload (read-only)
    .Empty => {}
    _ => {}                        // anything else
}
```

Arms are tested top to bottom and there is no fall-through. A `match` on an enum, a union or `bool`, statement or expression, must be exhaustive: cover every variant (both values for `bool`) or add `_`. A `match` expression on any other type also needs a `_` arm; a `match` statement on an integer, string or pointer may fall through to the next statement.

## 6. Builtins and formatting

The compiler itself knows only these names: `sizeof`, `alignof`, `embed`, `panic`, `assert`, the type `Fmt`, `Self`, `error`, `Option` (the meaning of `?T`), `async` and `await` (syntax only), the prelude types `Poll` and `Context` (the types used by the generated `poll` of an async function, see section 7b), the method name `poll` and the variant names `Ready` and `Pending` of `Poll` (used by `await`, the generated `poll` and the inference of section 7b) and the runtime helpers `__panic`, `__oob`, `__ovf`, `__str_eq`, `__errname`, `__rt_init` (called first by `main` and by the test runner unless `--freestanding`; the prelude uses it to install the crash handler). Everything else is ordinary code in `std/std.zk`.

| Builtin | Notes |
|---|---|
| `embed("file")` | the file's bytes as a `str` constant, path relative to the source file (read at compile time) |
| `panic(...)` | prints `panic: ` and the formatted arguments with file:line, exits 1; lowers to `__panic` |
| `assert(cond)` | prints `assertion failed (file:line)`, exits 1 |

### `Fmt`

A call whose callee has a last parameter of type `Fmt` receives **all remaining arguments** as one `Fmt` value: a string literal is parsed for `{expr}` / `{expr:spec}` holes, every other expression becomes one hole, and the pieces are joined by single spaces. A `Fmt` lives on the stack of the caller (no heap, no `printf`); it is only built at call sites. An interpolated string anywhere else is a compile error. If the only remaining argument already is a `Fmt`, it is passed through.

The std defines, in plain Zark: `print`, `println`, `eprint`, `eprintln`, `!str bprint(u8[] buf, Fmt f)` (`error.NoSpace` if it does not fit, one byte is kept for a NUL), `!void sprint(List<u8>* out, Fmt f)`, and `Writer { ctx, write_fn }`. Your own functions can take a `Fmt` too. Arguments are evaluated before the fixed arguments of the same call.

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
- `align(N) T name = v;` before a global variable aligns it to `N` bytes (a power of two, page tables and DMA buffers). `align(N) struct S { ... }` aligns the struct (and every variable, array element and field of that type) to `N` bytes and pads its size to a multiple of `N`; the native backend supports locals up to 16 and switches to LLVM for more.
- `asm<R>("template", "constraints", args...)` (`R` defaults to `void`): LLVM inline asm with `sideeffect`. Braces in the strings are written `\{` and `\}`. The native backend encodes the templates used by the prelude (`Cpu`, `Port`, `Atomic`) and rejects others with a message; `--llvm` accepts any.
- `a +% b`, `a -% b`, `a *% b` are integer operators that always wrap (same precedence as `+` `-` and `*`); they are never checked by `--check-overflow` and never get `nsw` under `--fast`.
- SIMD vectors: `f32x4`, `i32x8`, `u8x16`, ... (element type `i8..i64`, `u8..u64`, `f32`, `f64`; 2, 4, 8, 16 or 32 lanes; at most 32 bytes) are LLVM vectors. `T(a, b, ...)` builds one, `T(x)` splats; `+ - * /`, `& | ^` and unary `-` work per lane (a scalar operand is splatted), `v[i]` reads and writes a lane, comparisons are not defined. A program that uses them is built through LLVM.
- `+`, `-` and `*` on integers in user code panic on overflow (`__ovf`) in a safe build; `--release`, `--fast` and `--freestanding` remove the check and they wrap, unless `--check-overflow` is given. A safe build omits a check only when it can prove the operation cannot overflow, for example `n - 1` after `if (n < 2) { return; }`, `i - 1` inside `for i in 1..n`, or `n + 1` after `if (n > 100) { return; }`; the panic still fires wherever the value is not provably in range.
- `--fast` is `--release` with `nsw` on signed `+ - *`; signed overflow is then undefined. Array and slice indexing is always emitted with `inbounds`.
- `--freestanding` links with `-nostdlib -static`, disables bounds checks, and accepts `-Wl,...`, `-T...`, `.S`, `.c`, `.o` arguments. An `export` function with a body replaces an `extern` declaration of the same name (for `memset`, `memcpy`).
- Prelude: `Cpu`, `Port`, `Bits`, `Atomic`, `Spinlock`.

## 7. Memory

```zark
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

Ownership: a parameter written `move T x`, or a method written `R name(...) move { ... }` (which consumes `this`), takes the argument over. When the argument is a plain local variable or parameter, the compiler rejects any later use of that variable until it is assigned again. The state is merged over `if`, `match`, `catch` and loops (a variable consumed in a loop body must be reassigned or left through `break`/`return`). `defer` and `errdefer` bodies are checked where they run. The check follows variable names only: copies of a pointer and field paths are not tracked. `move` is contextual, not a keyword. The prelude marks `Allocator.free`, `Allocator.destroy` and the `deinit`/`close`/`join` methods.

Borrows: a method written `R name(...) borrows { ... }` returns a pointer or slice into the receiver, and one written `invalidates` may move or free what earlier pointers refer to. When a local variable is initialized or assigned from a call to a `borrows` method of a local variable `c`, from `&c.f`, `&c[i]`, `c[a..b]`, or a longer place such as `&c.items[i]` or `&c.l.items[i]`, any later use of that variable after `c` was consumed or after an `invalidates` call on the slice or pointer that holds the element is an error. A pointer stored inside another struct is not followed. A pointer or slice into a local array or struct value (`&x`, `&x.f`, `&a[i]`, `a[lo..hi]`) cannot be returned, and cannot be stored through a pointer parameter or into a global. The prelude marks `List.push/append/insert/reserve`, `Map.put/remove` as `invalidates` and `List.at/slice`, `Map.get_ptr` as `borrows`. Like `move`, both words are contextual.

A loop `for (T x : seq)` whose `seq` is a `borrows` call, a container variable or field path (`list`, `this->items`), or a variable that holds a borrow, may not reach its next iteration after an `invalidates` call on that container; `break` and `return` after the call are fine. Borrows and `invalidates` calls follow field paths rooted at a local variable (`this->items`, `s.list`), not only plain variables.

A struct declared `owned struct S { ... }` is a resource that must be consumed. A local variable of such a type that is initialized from a call (not from a struct literal) must, on every exit of its scope, including the exits taken by `?` and by `break`/`continue`, have been passed to a `move` parameter or `move` method, passed or assigned elsewhere as a value, or returned. Dropping a value of such a type (`f();` or `_ = f();`) is an error. A variable initialized by a call that takes a closure capturing locals, or the address of a local, counts as pointing into those locals: it cannot be returned or stored through a pointer parameter. The prelude declares `Thread` `owned`, with `join` and `detach` as `move` methods. `owned` is contextual.

Copying a value of a resource type is a move. A resource type is an `owned` struct, a struct with a method that consumes its receiver (`deinit() move`, `close() move`, ...), or any struct or union, array or error union with such a type in a field, variant or element: that covers `List`, `Map`, `Arena`, `Thread`, `Executor`, the generated `_own` handles, `struct Holder { List<i64> l; }` and `union Either { List<i64> l; i64 n; }`. The check follows nested fields without a depth limit and treats a by-value cycle as a resource. `auto y = x;`, `y = x;`, a field of a struct literal (`S{ .f = x }`), passing `x` (also a field, `f(h.l)`) to a parameter that is not `move`, and `return x` copy the bytes and therefore consume `x`; any later use is the "used after consumed" error. `auto y = h.l;` and `y = h.l;` move that field path, and assigning the path again makes it valid once more. `auto y = *p;` on any resource type is an error, because the copy would alias what the pointer points at: use `clone()` or pass the pointer on. A field or element reached through a pointer or a slice (`this->l`, `hp->l`, `s[0]`, `(*p).l`) is the same: copying it out, returning it, passing it by value or moving it into a `move` parameter is an error, because the storage still belongs to the pointer or the container. A field or constant index rooted in a local value (`h.l`, `l.items[0]`) is owned and moves normally. For an independent copy use `x.clone()` on `List`/`Map` (allocated from the original allocator) or build a new value. `&x` passes a pointer and does not move. Iterating a container whose element is a resource (`for (auto x : list_of_lists)`) binds `x` to a non-owning copy of the element: reading it and calling its `borrows` methods is fine, but moving it — passing it to a `move` parameter, calling a `move` method such as `deinit`, or copying a resource field out (`auto y = x.inner`) — is an error, because the container still owns those bytes. Calling an `invalidates` method on it or on a resource field (`x.inner.push(v)`) is an error too: the copy's header would change while the container still points at the old buffer. A write to a plain field (`x.n = 1`) changes the copy, not the container. Take an element out with `pop`/`remove_at`/`swap_remove`, or index the container and use `move_out(&c[i])`. A closure cannot capture the loop variable either: the capture is a pointer to the copy, so it could change the copy's resource fields. A non-resource element is still copied by value. A resource element read by a runtime index (`l[i]` with a non-literal `i`) has no path the check can follow, so it is rejected: the copy would alias storage the container still owns. A constant index rooted in a local is tracked and moves that path. Inside a method of the container itself (`this->items[i]` in `pop`, `remove_at`, `swap_remove`, `take`) the read is trusted to hand the element over, since only the container knows whether the slot is still live. `List.get` and `List.last` return the element by value, so they are rejected for a resource element (the index has no path, and `last` goes through `at()`); borrow one with `at(i)`, or move it out with `pop`/`remove_at`/`swap_remove`. `Map.get` and `Map.get_or` are rejected for a resource value for the same reason; borrow with `get_ptr(key)`. `move_out(&x)` is the explicit byte-wise move out of a place, for code outside the container that takes an element out of its storage (the native backend's block pruning uses it): the caller must treat `x` as dead and never free both the result and the storage. It is the explicit way to bypass the copy check, so it belongs in a container implementation, not in ordinary code. The other bypass is the receiver-rooted read above, which is limited to the container's own methods. `match (x)` on a resource union consumes `x` (copying the union is a move): the arm binding owns the payload and a later use of `x` is the used-after-consumed error. Inside a `for` over a container of resources the binding is a non-owning view, like the loop variable. `x orelse d` and `x catch d` copy the payload out, so a resource optional or error union in a place is consumed by the unwrap: using `x` after it is the used-after-consumed error.

## 7a. Compile-time evaluation

`comptime EXPR` (a prefix operator, binding like unary `-`) evaluates `EXPR` while compiling and uses the result as a constant. The compiler builds the program with a generated `main` that runs `EXPR` (all functions, constants and the prelude are available; local variables and type parameters are not), runs it, and reads the bytes back. The type must be plain data: integers, floats, `bool`, enums, `str`, and arrays or structs of those; a `void` expression is run for its effects. A result of an array or struct type lives in read-only data and is indexed in place. A top-level `comptime EXPR;` runs before code generation, so `comptime assert(sizeof(T) == 16);` is a static assertion. Each distinct expression is run once per compilation, in a child compilation of the same program. `comptime` inside a string interpolation is not supported. The prelude helpers `__ct_emit` and `__ct_emit_str` carry the result.

## 7b. Async

`async` is a contextual modifier written before the return type of a function, a method or a generic function: `async i64 f(i64 a)`, `async !str fetch(Conn* c)`, `static async i64 make()`, `template<T> async T id(T v)`. `await` is a contextual prefix operator. Both words stay ordinary identifiers elsewhere. `async` on an `extern` or `export` function is an error.

```zark
async !str fetch(Conn* c, str path) {
    c.write_all("GET {path}\n")?;
    auto line = await c.read_line();
    return line;
}
```

**Frames.** Calling an async function does not run it. It returns its frame by value, in state 0: a struct made by the compiler (one per function and per generic instance) with the state number, the copied arguments, the result slot, every local and compiler temporary of the body, and the frames of the futures it awaits. So `auto f = fetch(c, "/");` works and `sizeof(f)` is the size of the frame; `sizeof(fetch(c, "/"))` gives it without running anything. For a method, `this` is an argument like any other (a pointer, not a copy).

**The `poll` protocol.** The frame has a method `Poll<T> poll(Context* cx)`. `Poll<T>` is the prelude union `{ T Ready; Pending; }`, `Context` holds a `Waker { void* data; fn(void*) wake_fn; }`. Any struct with a method of that shape is a future, so a library writes leaf futures by hand and `await` treats them like frames. An async function without a result type is a future of `Poll<bool>` that yields `true`. The executor polls a task again only after its waker was called, so a future that returns `Pending` must have arranged for that. `await e` on a type without such a method is an error. The operand is a full expression: `await *p` dereferences `p` and awaits the value, so `p` may point at a future, and an `i64` behind the pointer is rejected.

**`await e`.** It evaluates `e`, stores the future in the frame, and polls it with the same `cx`. If it is pending, the current `poll` returns `Pending` and the next `poll` resumes at the same place. On `Ready(v)` the expression is `v`. `return` and `?` in an async function store the result in the frame and return `Ready`. `defer` and `errdefer` run at the usual places, once per exit.

**Where `await` may appear.** Nothing computed earlier in the same expression may be alive across a suspension, so `await` is accepted only in these positions, optionally followed by `?` or `catch`:
- as a whole expression statement: `await f();`
- as the initializer of a declaration: `auto v = await f();`
- as the right side of `=` to a local variable: `v = await f();`
- as the operand of `return`: `return await f();`
- as the whole condition or scrutinee of `if`, `while` or `match`: `if (await ready())`, `while (await more())`, `match (await next()) { ... }`. A `while` condition is awaited again on every iteration.

Anything else is rejected with "bind the result to a variable first": an argument, an operand (`await f() == 2`, `(await f()) as i64`), `p.f = await e`, `a[i] = await e`, `x += await e`, an `await` inside a `catch |e| { ... }` block or inside a block arm of a `match` expression that is part of a larger expression (`auto v = g() catch |e| { await h(); 1; };`). `await` is also an error in `defer` and `errdefer` (also in a block), in a closure, and outside an async function. The statement forms `if`, `while`, `match`, `for` and plain blocks may contain `await` in their bodies as usual.

**Recursion.** A frame cannot contain itself. A call chain that would (an async function awaiting itself, or a cycle through several) is an error that says the recursive call has to go through a pointer to a separately allocated frame.

**Pinning and ownership.** Once polled, a frame holds pointers into itself (locals whose address was taken, the awaited child frame), so it must not move. The compiler checks what it can see by name: `await f` consumes the local variable `f` (a later use is the "used after consumed" error of section 7), and so does passing it to a `move` parameter such as the executor's `spawn(move F fut)`. A future that was not started may be moved freely. `await h.y` consumes the field path `h.y`, so a second `await h.y` is the same "used after consumed" error, and copying a frame after it was polled (`auto g = f;` after `await f`) is rejected. A future reached through a pointer or an array element is still not consumed by name.

**Borrows across `await`.** The executor may run other tasks while one waits, so an `await` counts like a call that `invalidates` every container borrow: a local pointer or slice that came from a `borrows` method (`list.at(i)`, `list.slice()`), and the iteration `for (x : c)` over a container whose `slice()` is a `borrows` method, may not be used after the `await` (a loop must not reach its next iteration). The pointer has to be taken again after the `await`. The limits are the ones of `invalidates` (section 7): names only; `&l.items[0]`, pointers derived from a copy of a borrowed slice, and pointers stored in structs are not tracked; a pointer passed into an awaited call lives in that child frame and is not tracked either. Pointers to the frame's own locals and slices of the arguments are fine across an `await`. The rule also applies to a `List` that is local to the async function, where nobody else could touch it.

**Cancellation.** Every future has `void cancel()`, and `spawn` and `block_on` require it. For an async frame it sets a flag, immediately re-enters `poll` at the suspension point, cancels the future it is awaiting, runs the `defer` and `errdefer` of every scope active at that point, innermost first (cancellation is an unfinished operation, so `errdefer` runs too), marks the frame finished and returns. The generated `cancel()` of a frame is idempotent: on a finished frame, and on a second call, it does nothing. A `JoinHandle` is single-use, like `take()` and `detach()`: `cancel()` invalidates it, discards a result that was not taken, and any later use (including a second `cancel()`) panics. `Executor.deinit` cancels every live task before freeing it; each task is cancelled once, so a hand-written `cancel()` need not be idempotent. `block_on` cancels its future when it returns `error.Deadlock` or `error.SystemCall`; `select` cancels the losing handle and `join` cancels both handles (a side that already produced a value is left alone); `detach` does not cancel, the task keeps running. `cancel()` also disarms the I/O registration a leaf future made (`Readable`, `Writable`, `Accept`, `Read`, `Write`), and the executor disarms whatever is left when the task ends. `cancel()` only disarms the registration its own future made: if another future armed the same descriptor and direction after it, that one stays armed.

**The library (`std/async`).** The module is plain Zark plus a small poller in `std/rt.c` (`vrt_poller_*`: epoll on Linux, kqueue on macOS; there is no Windows reactor). It is single-threaded and uses the `Allocator` given to the executor, nothing else allocates.
- `Executor::init(a)` / `deinit()` (an `owned` struct). Tasks keep a pointer to it, so it must not move after the first `spawn`.
- `ex.spawn(fut)` takes a future by `move`, puts it in memory from the executor's allocator and returns `JoinHandle<T>`; spawned tasks run while some `block_on` is running. `ex.block_on(&fut)` polls a future and the executor until the future is ready, and returns `error.Deadlock` if nothing can make progress. Its result is `!T` where `T` is the future's output, so a future of `!i64` makes `auto r = ex.block_on(&f)?;` a `!i64` (one `?` unwraps the executor error, a second one the task error; `ex.block_on(&f)??` gives the plain value). `JoinHandle<T>` has `done()`, `take()`, `detach()` and is itself a future (`await h`). A handle is used up once its result was taken (by `take()`, by awaiting it or by `block_on(&h)`) or it was detached; any later use of it or of a copy of it panics, and so does `take()` before `done()`. `join(a, b)` takes two `JoinHandle`s (from `spawn`) and is a future that yields `Pair<A, B>` when both are done. `select(a, b)` is a future that yields `Select2Result<A, B>` (`.First(v)` or `.Second(v)`) from whichever handle finishes first and cancels the other.
- The result type of `spawn` and `block_on` is inferred: when a call to a generic function leaves exactly one type parameter unknown and exactly one of the known type arguments is a struct whose `poll` returns `Poll<X>`, the unknown parameter becomes `X`. So `auto h = ex.spawn(chain())?;` and `auto r = ex.block_on(&f)?;` need no annotation, for async frames and hand-written futures alike. An annotation such as `async::JoinHandle<i64> h = ex.spawn(f)?;` or `i64 r = ex.block_on(&f)?;` still works and is checked; explicit type arguments (`ex.block_on<Countdown, i64>(&f)`) are needed only when the future's `poll` is itself generic. For a future whose result is itself an error union `!X`, the inferred result of `block_on` is `!!X` (unwrap both with `??`), while the annotation `X r = ex.block_on(&f)?;` merges the two.
- `Channel<T>::init(a)` / `deinit()` (an `owned` struct) is an unbounded FIFO between tasks on one executor. `send(v)` never waits; it allocates and returns `error.Closed` after `close()`. `recv()` is a future of `!T`; it yields `error.Closed` when the channel is closed and empty. `close()` wakes the receivers. `select_recv(a.recv(), b.recv())` yields `SelectRecvResult<!A, !B>` (`.First(v)`/`.Second(v)`) from the channel that is ready first and unregisters the other; cancelling a suspended `recv` unregisters its waker. A channel is confined to one executor: the executor is single-threaded and `std/thread` has the blocking `Channel<T>` for sharing between threads.
- `Sleep::after(&ex, ms)` is a future that is ready after `ms` milliseconds; `Readable::on(&ex, fd)` and `Writable::on(&ex, fd)` are ready when the descriptor is.
- `TcpListener::bind(&ex, host, port)` has `accept()`; `TcpStream` has `read(buf)` and `write(data)`; these return futures of `!TcpStream`, `!i64` (0 means the peer closed) and `!i64` (the byte count, all of `data` is written). `TcpStream::connect(&ex, host, port)` is a blocking call that returns a nonblocking stream. `close()` consumes the listener or the stream.
- One waker is kept per descriptor and direction.

## 8. C interop

- `extern` declares a C function and `export` defines one.
- `void*` is C's `void*`. String literals pass as `u8*` (they are NUL-terminated). Any other `str` must be passed as `s.ptr` explicitly.
- Supported C ABIs: System V x86-64 (Linux, macOS on Intel) and AAPCS64 (Linux arm64 and Apple arm64). AAPCS64 code is produced only through LLVM: the native backend exists only for Linux x86-64, so on arm64 every build uses the LLVM path. The target is the host; `zark ir` and `zark cbind` take `--arch x86_64|aarch64` and `--os linux|macos` to produce the IR or bindings of another target (other commands refuse them). `long double` is not supported on any target.
- A call to a variadic `extern` function classifies its fixed parameters and its result exactly like a non-variadic C function. The variable arguments follow the default promotions (`f32` to `f64`; `i8`, `i16`, `u8`, `u16` and `bool` to a 32-bit integer; pointers as they are), and a struct or union among them is coerced as C passes it (on x86-64 by its System V class, sharing the register count with the fixed part, with the number of vector registers used in `%al`; on arm64 like a fixed argument, and on Apple arm64 LLVM puts all variable arguments on the stack from the target triple). Slices and arrays are rejected there. A variadic function cannot be used as a `fn` value and there is no variadic `fn` type, so these calls go only from Zark to C and only directly.
- Structs (and slices) are passed to and returned from `extern` functions by value following the C ABI of the target. On x86-64 (System V): up to 16 bytes in registers by eightbyte class (INTEGER or SSE), larger or when the registers run out on the stack (`byval`), large results through a hidden pointer (`sret`). A union is the C struct `{ int32_t tag; _Alignas(8) union { ... } payload; }`, where `tag` is the zero-based index of the variant in declaration order (a variant without a payload counts too): the tag eightbyte is INTEGER and each payload eightbyte merges the classes of all variants (INTEGER wins, SSE only when every variant there is `f32`/`f64`), so `union U { f64 A; f32 B; }` travels as INTEGER + SSE. On arm64 (AAPCS64): a homogeneous floating-point aggregate (1 to 4 `f32` or 1 to 4 `f64` leaves, also through nested structs and arrays, without padding; empty structs are ignored, a zero-length array disqualifies) travels in consecutive vector registers as `[N x float]`/`[N x double]` (on Linux with `alignstack(8)`, or 16 when a member is 16-aligned) and returns in them; any other aggregate up to 16 bytes travels in one or two general registers (`i64`, `[2 x i64]`, or `i128` with an even register pair when it is 16-aligned) and returns as an integer of its size (`[2 x i64]`/`i128` above 8 bytes). For a parameter Linux takes that alignment from the members, ignoring an `align(16)` on the struct itself (as clang does for `__attribute__((aligned(16)))` on a C struct), Apple and all results take the full alignment; larger ones are copied by the caller and passed by pointer (not `byval`) and returned through `sret` (x8). A Zark union is never an HFA (its tag is an integer). When the registers run out, LLVM places the whole aggregate on the stack. Small integer parameters and results (`i8`, `i16`, `u8`, `u16`, `bool`) carry `signext`/`zeroext` on x86-64 and Apple arm64; on Linux arm64 they carry none, as clang emits them.
- SIMD vectors in the signature of an `extern` or `export` function, of a `fn` type in such a signature, or of a Zark function used as a `fn` value travel as the C vector type of the same size (`float __attribute__((vector_size(16)))` for `f32x4`): 16-byte vectors on every target and 8-byte vectors on arm64, in vector registers (on x86-64 they count against the eight SSE registers like `f64`). Other sizes, and vectors inside a struct or union passed or returned by value there, are rejected, because C passes them in ways the compiler does not reproduce. Interface methods are not checked: both ends of their calls are Zark.
- A `fn` value is a C function pointer. When a Zark function whose signature contains an aggregate by value (on Apple arm64 also a small integer) is used as a value, the compiler emits one canonical C-ABI thunk for it (`name$c`); any other signature uses the function itself. `export` emits the C-ABI thunk under the exported name and keeps the Zark body under `name$z`, so direct Zark calls keep the internal ABI. Indirect calls use the same C ABI; `fn[]` closures are not C function pointers.
- An empty struct has size 0: it consumes no argument registers and C does not return it through a register. It is omitted from the C signature and the matching Zark argument is still evaluated. This follows C (GNU), where an empty struct has size 0; C++ gives it size 1.
- `zark run main.zk x.c y.cpp lib.o -lfoo` compiles and links everything, using `clang++` if C++ is present.

### Build flags

`run`, `build` and `test` sort their extra arguments:

- compile flags `-I…`, `-D…`, `-U…`, `-std=…`, `-f…`, `-W…` (not `-Wl,`) and `-pthread` go to every C/C++ source and to every imported header. A C standard (`-std=c11`) applies only to `.c` files and C headers, a C++ one (`-std=c++17`) only to `.cpp`, `.cc` and `.cxx` files and C++ headers;
- link arguments `.o`, `.a`, `.so`, `-l…`, `-L…`, `-Wl,…`, `-T…`, `-nostdlib`, `-static` go to the linker;
- everything else is a source file.

A Zark file without `main` can be linked with a C `main`, and a set of C/C++ sources needs no Zark file at all.

### Manifest keys

The `[build]` table of `zark.toml` (paths are relative to the manifest):

| Key | Meaning |
|---|---|
| `sources` | C/C++ files compiled and linked in |
| `libs` | libraries, linked as `-lNAME` |
| `lib-dirs` | library directories, passed as `-L` |
| `include` | include directories, passed as `-I` |
| `defines` | macros, passed as `-D` (`"NAME"` or `"NAME=VALUE"`) |
| `std` | language standard, passed as `-std=` |
| `cflags` | other compile flags, as written |
| `pkg-config` | packages whose `pkg-config --cflags --libs` output is added |
| `by_value` | C++ record names (unqualified or qualified, `"ImVec2"`, `"ns::Vec"`) that a C++ binding takes by value as `const T&` parameters even when the signature can reach their storage (`zark cbind --by-value=A,B`) |
| `flags` | default Zark flags (`-O`, `--release`, …) |
| `out` | output path of `zark build` |

A project whose `package.main` file does not exist but that lists `sources` is built from those sources alone.

### Object cache

Each C/C++ source is compiled to `.zark-cache/obj/NAME-HASH.o`, at most 8 at a time (`ZARK_JOBS` overrides). The hash covers the compiler (`clang` or `clang++`), the optimization level, the path, the flags and the source text. The headers the source includes (from clang's `-MD` output) are checked as well, so changing a header rebuilds what uses it. Cache entries are written atomically, so parallel builds share them safely.

### `import "x.h"`

`import "x.h";` or `import "x.h" as name;` binds the declarations of a C header. The header is looked up in the directory of the importing file, then the `-I` directories, then the system include path; it is run through `clang -E` with the compile flags of the build (C++ `-std=` flags are dropped). The result is the same Zark text that `zark cbind` prints, compiled as a module; `as name` puts it under `name::`. Static inline functions get a C wrapper, extern variables and bitfields C accessors; that C file is compiled and linked automatically. Each variable accessor is compiled only when the program uses its `name_ptr()`, so a declared variable that the program never touches need not exist at link time.

The binding is cached in `.zark-cache/cbind/` and reused while the clang version, the compiler's binding generator (its key includes a hash of that part of the compiler, so a binding from another Zark build is not used), the flags and every header it read stay the same. The cache does not track `CPATH` or other environment variables. `import` does not print the warnings for skipped declarations; run `zark cbind` to see them.

A header with a C++ extension is bound as a C++ header (see C++ headers below); any other extension, including a C++ `.h`, is parsed as C. Without `as`, two imported headers that both include the same header are an error (import one header that includes both). With `as`, each import gets its own copy of the shared declarations, and those are different Zark types.

### `zark cbind`

`zark cbind header.h [compile flags] [-o out.zk] [--inline-c out.c]` prints the bindings for one header (to stdout or `out.zk`) and a warning on stderr for each declaration it skips. `--inline-c` writes the C wrappers for static inline functions and the accessors of extern variables and bitfields; that file must be compiled into the program next to `out.zk`, with the same flags that change types (`-fsigned-char`, `-funsigned-char`, `-fshort-enums`, `-D` and `-I`) as the `cbind` run, or the accessors read different types than the binding declares. Compiled as it is, it defines every variable accessor; with `-DZARK_PICK` it defines only those whose `ZARK_USE_HASH_name` macro is also defined, which is how `import` links only the used ones. The C file includes the header by its absolute path and the wrapper names hash that path, so the pair is specific to the machine and checkout that produced it: it is for inspection, not for committing.

| C | Zark |
|---|---|
| `char`, `signed char`, `unsigned char` | `i8` where `char` is signed (x86-64, Apple arm64), `u8` where it is unsigned (Linux arm64; clang defines `__CHAR_UNSIGNED__`, `-funsigned-char` too); `i8`; `u8` |
| `char *`, `const char *` (also through a typedef of `char`) | `u8*` (C strings) |
| `short`, `int`, `long`, `long long` | `i16`, `i32`, `i64`, `i64` (unsigned: `u16`, `u32`, `u64`, `u64`) |
| `size_t`, `ptrdiff_t`, `ssize_t`, `intptr_t`, `uintptr_t` | `usize`, `i64`, `i64`, `i64`, `u64` |
| `wchar_t`, `char16_t`, `char32_t` | the integer type the C library defines (`i32` or `u32`, `u16`, `u32`) |
| `_Bool` (`bool` from `<stdbool.h>`), `float`, `double` | `bool`, `f32`, `f64` |
| `volatile T` | `T`: Zark has no `volatile`, so loads and stores through the bound pointers are plain and may be merged or removed by the optimizer; a variable that is itself `volatile` gets no accessor |
| `T *`, `const T *`, `void *` | `T*`, `T*`, `void*` |
| `T a[N]` (field), `T a[]` (parameter) | `T[N]`, `T*` |
| `R (*)(A, B)` | `fn(A, B) -> R` |
| `typedef T name;` | `type name = T;` |
| `struct`, nested anonymous struct | `struct` with the same layout, anonymous parts named `outer__anonN` |
| incomplete struct | empty struct, used through pointers |
| struct or union aligned above 8 (`__attribute__((aligned(16)))`, `_Alignas(16)` member) | `align(N) struct`: with the C fields when clang's layout equals the natural one rounded to `N`, otherwise opaque storage of the same size and alignment |
| `union` | struct `{ uN[k] storage; }` with accessors `as_member()` returning a pointer; in a union of at most 16 bytes (also one aligned to 16) an SSE eightbyte is stored as `f64` or `f32` (`storage_hi` holds the second eightbyte when the two differ), so size, alignment and System V class match the C union |
| `enum E { A, B }` | `type E = i32;` (or the integer type that holds the values) plus `const auto A = 0;` … |
| `#define N 42`, string, float or char constant | `const auto N = 42;` |
| function, variadic function | `extern` declaration |
| `static inline` function | `extern` wrapper `zark_inl_HASH_name` in C plus a Zark function `name` that calls it |
| struct with bitfields | opaque storage of the same size and alignment with `get_f()` and `set_f(v)` for each named bitfield `f`, through C accessors `zark_bf_HASH_…` in the inline C file; the value has the declared type (`_Bool` is `bool`), C does the masking and sign extension; unnamed and zero-width bitfields get none |
| `extern T name;` | `T* name_ptr()`, the address of the variable from a C accessor `zark_var_HASH_name`; `extern T name[];` gives `T* name_ptr()` to the first element; `T` follows the `char` row for a plain `char` variable (`extern char c;` gives `i8* c_ptr()` where `char` is signed), the `u8*` string rule applies only to a variable that is itself a `char*`; `const` is dropped as for pointers |

Fields, parameters and types whose names are Zark keywords or type names get a trailing `_` (`type_`, `str_`); functions with such names are skipped. A declaration that uses a skipped one is skipped too.

Limits of C headers (those of C++ headers are in the next subsection): for a target other than the host, clang reads the system headers it finds for that target, which on a host without a sysroot for it are the host's own: `#include <stdio.h>` from x86-64 glibc fails for `--arch aarch64` (`__float128 is not supported on this target`), so the target's headers have to be passed with `-isystem`. The storage of a union picks its element types by the System V classes on every target; on arm64 a record passed or returned by value is accepted only when the Zark type and the C record are both non-HFA or the same HFA (same base type and count), otherwise the function is skipped as `opaque record by value` (for example a union of `float` and `double`, which System V passes in SSE but AAPCS64 in a general register, or a record that loses a flexible array member, or one with a member of a skipped type other than `__int128`, such as `_Complex`, `_Float16` or `long double`, which can make it an HFA); on Linux arm64 a record aligned to 16 and passed (not returned) in registers is also skipped as `over-aligned record by value` when its alignment comes from an attribute inside the record (`_Alignas` on a member) or when the alignment of a member's type is unknown to the binding (a member of a skipped type, such as an `aligned` typedef or `__int128`), because AAPCS64 classifies it by the members' alignment while the binding carries it as `align(16)` on the struct. Skipped with a warning: `long double`, SIMD vector types (`vector_size`, `ext_vector_type`; a record holding one becomes opaque storage, and passing or returning such a record by value is skipped as `vector in a record by value` on every target), `__int128` (Zark has no 128-bit integer; a record holding one becomes opaque storage), `_Complex`, `_Atomic`, bitfield members of unions, bitfield accessors of anonymous nested records, thread-local variables (`_Thread_local`, `__thread`: TLS is not supported), `static` variables (each C file has its own copy) and variables declared without `extern`, `volatile` variables (`extern volatile T v;`, `T* volatile p;`, also through a typedef or as an array), variables marked `unavailable` (also through `availability(...,unavailable)` for any platform), a variable whose `name_ptr` is taken by another C declaration (accessors are emitted after all other declarations, so the C name wins in any order), function-like macros, variadic static inline functions, variadic function pointer types, plain `static` functions, records passed by value whose System V class the binding does not reproduce exactly (`opaque record by value`), on x86-64 records aligned above 8 passed or returned by value when they are larger than 16 bytes or leave an eightbyte without a class (`over-aligned record by value`), and records passed by value in function pointer types. A record with a flexible array member loses that member, or becomes opaque storage when its layout would differ.

### C++ headers

`import "x.hpp" as name;` and `zark cbind x.hpp [compile flags] [-o out.zk] [--inline-c out.cpp]` bind a C++ header. A header is C++ when its extension is `.hpp`, `.hh`, `.hxx` or `.h++`. A `.h` file is always parsed as C; a C++ header that ends in `.h` is imported through a one-line wrapper (`x.hpp` containing `#include "x.h"`), and the C parse error of a C++ `.h` is followed by the line `hint: if this is a C++ header, import it through a .hpp file that includes it`. The compile flags are those of the build, with a C++ `-std=` kept and a C one dropped (the mirror of C headers). Without `as`, two imported C++ headers that declare the same namespace are an error (`import them with 'as' or through one header that includes both`).

The binding is two files, like the C one: a Zark module and a C++ file of shims (`--inline-c`, or `KEY.cpp` next to `KEY.zk` in the cache). A shim is an `extern "C"` function named `zark_cxx_HASH_N` that does one C++ operation: a call, a constructor, a destructor, the address of a variable, a bitfield access or a cast. Its signature has only scalars, enums as integers and pointers, so a class never crosses the C ABI by value; the Zark wrapper copies value types in and out through pointers. Declarations from system headers (the compiler's include directories and `-isystem`) are not bound, so `std::` names appear only through the shims described below. clang reads the header as a JSON AST; the bindings need `clang++`.

| C++ | Zark (under `import "x.hpp" as ns;`) |
|---|---|
| namespace `geo`, nested `a::b` | an empty struct `geo`, `a_b`; its functions are static methods: `ns::geo::area(s)`, `ns::a_b::f()` |
| function at global scope | a plain function: `ns::f(x)` |
| class or struct `geo::Shape`, nested `Outer::Inner` | `struct geo_Shape`, `struct Outer_Inner` (path joined with `_`); types are not nested in the namespace struct |
| `enum E { A, B }` | `type E = i32;` (or the fixed underlying type) and `const auto A = 0;`; the enumerators of an enum inside a namespace or class get the path of that scope as prefix (`geo_FlagA`, `Box_Top`) |
| `enum class geo::Kind : uint8_t { Circle }` | `type geo_Kind = u8;` and `const auto geo_Kind_Circle = 0;` (the enumerators of a scoped enum are prefixed with the enum path; `enum class` without a fixed type is `i32`) |
| `constexpr` or `static const` number, `bool` or `char` at global, namespace or class scope | `const auto geo_N = 42;`, `const auto Limits_Max = 7;` |
| object-like macro with a constant value (number or string) | `const auto MAC_NUM = 42;`, as for C headers, from `clang++ -E -dD`; macros of system headers are not bound |
| `typedef` and `using` of a type | `type name = T;` |
| variable, static data member | `T* name_ptr()`: a static method of the namespace struct or of the class, a plain function at global scope |
| `extern "C"` function with a C signature (scalars, pointers, enums) | an `extern` declaration of the C symbol, no shim, no namespace |
| method, `this` | a method of the struct; `const` methods are `const`; static methods are `static` |
| template specialization `Box<int>`, `Vec<unsigned short>`, `Arr<int, 4>` | `struct Box_i32`, `Vec_u16`, `Arr_i32_4`: the template name and one token per argument (the canonical type, so `ImWchar` and `unsigned short` are the same; `long` is `i64l`, `long long` is `i64ll`, a pointer adds `p`, a negative number `n`, an enum argument its value) |
| `std::string`, `std::string_view`, `std::vector<T>`, `std::unique_ptr<T>` | see below |
| printf-style variadic function (`__attribute__((format(printf, …)))`) with the format string as its last fixed parameter | the variadic part is removed: `Text(u8* fmt)`, and the shim calls `Text("%s", fmt)`, so the string is printed as it is and formatting is done in Zark (`bprint`) |

A class or struct becomes a Zark struct with clang's size and alignment, taken from `-fdump-record-layouts`, flattened: the public fields of the class and of its public non-virtual bases are at their offsets, and everything else (private and protected fields, the vtable pointer as `void* __vptr`, virtual bases, fields hidden by a derived field of the same name, fields of skipped types) is padding `u8[n] __padN`. A struct gets `align(N)` where the alignment would come out wrong, and becomes opaque storage of the same size and alignment (`opaque NAME: reason`) when its layout cannot be reproduced (a packed struct, a union with non-trivial members). Bitfields are padding with `get_f()` and `set_f(v)` accessors, anonymous unions and structs follow the C rules, and a literal in-class initializer (`float x = 0;`) is the default value of the Zark field. Reopened namespaces are merged.

Classes are of two kinds. A value type is trivially copyable and not abstract (`ImVec2`): Zark copies, stores and returns it freely, it is passed to and returned from shims by pointer, its single constructor with parameters (other than a copy or move) is the Zark constructor `T(args)`, any other constructor is `static T make[_suffix](args)`, and operators work on it (below). Every other class is non-trivial (a user-provided destructor or copy operation, a virtual function). A non-trivial object is used only through pointers: copying one in Zark (`auto x = *p;`) compiles but makes a bitwise copy that C++ does not know about, and the compiler does not reject it, so such objects must not be copied. A C++ pointer or reference result is a Zark pointer and is never destroyed by Zark.

To create a non-trivial object from Zark, every constructor the class declares, other than a copy or move constructor, gives `static !T_own create[_suffix](Allocator a, args)`, which takes `sizeof(T)` bytes from `a` and runs the constructor there. `T_own` is an `owned struct` with `ptr`, `mem`, `size` and `a`, and these methods: `get() borrows` returns the `T*`; `deinit() move` runs the destructor (virtual if it is) and gives the memory back to `a`; `release() move` returns the `T*` without destroying it; `clone(Allocator a)` copies the object when the class has a copy constructor. Because the type is `owned`, the existing checks apply: a handle that is not consumed on every path is an error (`not consumed on every path`), a pointer from `get()` used after `deinit()` is the borrow error (`may have moved or freed`) and a use of the handle after `release()` is `used after 'release'`. The usual form is `auto x = T::create(a, …)?; defer x.deinit();`. A handle whose `a` is zero came from C++ (a `std::unique_ptr<T>` result) and `deinit()` deletes it. A non-trivial class that can be assigned has `assign(T* other)` and `assign_move(T* other)`, the copy and move assignment. A non-trivial class passed by value into C++ is `T*` in Zark and is copied (or, for a move-only class, moved) by the shim, so the Zark object stays valid (moved-from in the second case); one returned by value takes an `Allocator` first and returns `!T_own`.

Methods, functions and constructors that share a name get parameter tokens: `name_t1_t2`, one token per parameter, built like the template argument tokens (`Combo_u8pc_i32p_u8pcpc_i32_i32`): a scalar is its Zark name (`i32`, `f32`, `u8` for plain `char`), a pointer adds `p`, a reference `pr`, a `const` pointee `c` (`const char*` is `u8pc`, `const V&` is `ui_Vec2prc`), a class or enum is its Zark name, a function pointer is `fn`. A name that is not overloaded is left alone. A `const` overload with the same parameters as a non-`const` one is dropped (`skipped X const: same parameters as the non-const overload`). A function with default arguments gets the full name and, for every shorter argument count `k` that C++ accepts, an extra `name_k` whose shim calls C++ with `k` arguments, so C++ supplies the defaults (`Begin`, `Begin_1`, `Begin_2`; `Button`, `Button_1`). A name that two generated names share is skipped on both sides with `name clash`.

References: `T&`, `const T&` and `T&&` are pointers, with one exception. A parameter `const T&` or `T&&` of a scalar, enum or value type is taken by value (`ns::ImGui::SetNextWindowPos(ns::ImVec2(24.0, 24.0), …)`); it stays a pointer when the function returns a reference or a pointer, or a record that holds pointers, because the result may refer to the argument. A `const T&` of a value type also stays a pointer when another parameter or the receiver can reach the same storage: a non-const pointer or reference to `void`, a scalar, an enum or a std type, to `T` or a record that holds `T`, or to a record whose pointer members lead to such a thing; a non-const receiver that is or holds `T`; a record with an unknown layout. A record named in the manifest key `by_value` is exempt from the aliasing rule and is taken by value, which is the project asserting that the callee does not modify the object behind the other parameter while it reads the reference. Returned references are pointers (`ImGuiIO& GetIO()` is `ImGuiIO*`).

Operators. On a value type, `+ - * / % == != < <= > >=` and unary `-`, member or free (a free `operator+(const A&, …)` becomes a method of `A` when `A` is a bound value type), are Zark operator methods: `a + b`, `a == b`. Every other bound operator is a named method: `[]` is `op_index`, `()` is `op_call`, `<<` and `>>` are `op_shl` and `op_shr`, `!` is `op_not`, prefix `++` and `--` are `op_inc` and `op_dec`, `+=` is `op_add_assign` and `-=` is `op_sub_assign`, `operator T()` is `to_T()` (`to_bool`, `to_f32`), and on a class that is not a value type the arithmetic and comparison operators are `op_add`, `op_sub`, `op_eq`, `op_lt`, …

Inheritance. For each public base `B` a derived class has `as_B()`, an upcast made by `static_cast` in a shim, which is correct for multiple and virtual inheritance. The public methods of the bases that the derived class does not hide by name are repeated on the derived struct and call through the upcast, so `circle.tag()` needs no `as_geo_Shape()`. Virtual functions are called through the ordinary method shims, so C++ dispatches. An abstract class gets no `create`. `T_own` has `into_B() move`, an upcast of the handle, when `B` has a virtual destructor.

Templates are bound only through specializations that exist in the AST: explicit instantiations (`template struct Box<int>;`, `extern template struct Box<double>;`, `template int twice<int>(int);`) and implicit ones that a bound declaration needs (a field of type `Vec<int>`). A specialization is a class like any other, and an instantiated function template keeps the plain function name (`twice`). A header gets more specializations through a wrapper `.hpp` that includes it and adds explicit instantiations (`template struct Stack<int>;`).

Standard library types are never bound from the AST; the shims below are recognized on the canonical type and emitted per binding, with no runtime module and no runtime symbol.

| C++ | Zark |
|---|---|
| parameter `std::string`, `const std::string&`, `std::string_view` | `str` (the shim builds the string from `ptr` and `len`) |
| result `const std::string&`, `std::string_view` | `str`, a view into C++ memory |
| result `std::string` | `!str f(Allocator a, …)`, copied into memory from `a` |
| parameter `std::vector<T>`, `const std::vector<T>&`, `T` a scalar or value type | `T[]` |
| result `const std::vector<T>&` | `T[]`, a view |
| result `std::vector<T>` | `!T[] f(Allocator a, …)`, copied into memory from `a` |
| result `std::unique_ptr<T>`, `T` a bound class | `T_own` with `a` zero |
| parameter `std::unique_ptr<T>` | `move T_own`; a handle whose memory came from a Zark allocator stops the program with `zark: cannot hand a Zark-allocated object to std::unique_ptr` |
| public `std::string` or `std::vector` field | padding, `skipped C::f: std:: member` |

A binding with shims that receive the `Allocator` (the string and vector results) carries `comptime assert(sizeof(Allocator) == 24);`, and the C++ file checks the `Allocator` layout it declares with `static_assert`.

Exceptions never cross into Zark. The shim of a function that is not `noexcept` has a `try` that catches everything and calls a function that prints `zark: uncaught C++ exception in geo::Shape::scale: WHAT` (`WHAT` is `what()` of a `std::exception`; for other exceptions the message ends after the name) and `abort()`s, so the process ends with SIGABRT. `noexcept` functions get no `try`, and neither does any shim when the compile flags contain `-fno-exceptions` or `-fno-cxx-exceptions`. A constructor run by `create` follows the same rule; `create` takes its memory from the Zark allocator, so a failure to allocate is the allocator's error. A Zark function passed to C++ as a `fn` pointer cannot throw.

Checked shims. Every shim names the C++ function it wraps through a cast that compiles only when the resolved signature is exactly right (`(void)static_cast<R (*)(A, B)>(&ns::f);`, a member-pointer type for methods), and constructors are checked with `static_assert(__is_constructible(…))`. When the binding is made, the shim file is compiled with `-fsyntax-only`; a shim that fails is dropped with its Zark wrapper and reported as `skipped NAME: shim does not compile: FIRST CLANG ERROR`. A declaration whose types cannot be resolved is skipped with its reason (below), never bound with a guessed type.

Pick and link. Each shim is compiled only when the program uses it: the C++ file wraps every shim in `#if !defined(ZARK_PICK) || defined(ZARK_USE_HASH_N)`, and the compiler defines `ZARK_USE_HASH_N` for each `zark_cxx_HASH_N` the program references (compiled as it is, without `-DZARK_PICK`, the file defines all of them). A function that the header declares and no linked file defines links fine as long as the program does not call it. The `.cpp` of an import is compiled and linked automatically, with `clang++`.

Cache. An import is cached in `.zark-cache/cbind/` as `KEY.zk` and `KEY.cpp`, under the rules of C headers: the key covers the clang version, the flags, a hash of the C++ binding generator (that part of the compiler) and every header read (from `-MD`). `import` does not print the warnings; `zark cbind` does. `zark cbind x.hpp --arch aarch64 --os linux|macos` is accepted, but the tests compare only the aarch64 Linux bindings of one record header (`tests/cxxbind/layout.a64.out`); they do not compile or run the shims for another target or check the `std::` shims against libc++.

Limits of C++ headers. A declaration that is not bound is reported by `zark cbind` as `skipped NAME: reason`, or `opaque NAME: reason` for storage without field access; nothing is bound with a guessed signature. Not supported, with no Zark side at all:

- subclassing a C++ class from Zark, and with it implementing or overriding a virtual function (an abstract class gets `skipped C::create: abstract class (implementing it in Zark is not supported)`);
- downcasts, `dynamic_cast`, RTTI, `typeid`;
- lambdas, closures and `std::function` crossing into C++ (only plain `fn` pointers do);
- exceptions as an error value: they abort;
- calls by mangled name: every C++ call goes through a shim (only `extern "C"` functions with a C signature are called directly).

Skipped declarations, by reason:

- names: `name clash` (two generated names are equal, both are skipped), `generated name X_own clashes with a bound type`, `ambiguous layout, another class has the same printed name`, `uses skipped NAME` (a declaration that mentions a skipped type), `unknown type 'T'`;
- types: `type 'T' is not supported yet` for `wchar_t`, `char8_t`, `char16_t`, `char32_t`, `long double` and `__int128`; `decltype types are not supported yet`; `enum with fixed underlying type` (a `char16_t` enum); `not a constant` (a `constexpr`, macro or default value that clang does not fold to a number, such as `(char16_t)-1`; `NAME default: not a constant` for a field initializer);
- records: `bitfield` (in a union), `bitfield in anonymous record`, `bitfield of a base class`, `flexible array member`, `reference member`, `overlapping member` (`[[no_unique_address]]`), `std:: member`, and the opaque storage reasons `packed`, `union with non-trivial members` and `layout not found`;
- functions: `va_list parameter`, `variadic function without a printf format attribute`, `variadic function with a non-printf format attribute`, `printf format string is not the last parameter`, `deleted constructor`, `deleted function`, `copying this class is not supported`, `abstract class (implementing it in Zark is not supported)`, `shim does not compile: …`, `same parameters as the non-const overload`;
- operators: `operator X is not supported` for `=` (see `assign`), `|`, `&`, `^`, `~`, `->`, `,`, `&&`, `||`, `<=>`, `new` and `delete`, `postfix operator is not supported`, `user-defined literals are not bound`, `operator receiver is not a bound value type` (a free operator whose first operand is not a bound value type), `operator overloads are not supported` (when an operator that would become a Zark operator method is overloaded in its scope, one overload is bound and the others are skipped);
- templates: `template without an instantiation; add 'template struct NAME<...>;' to a wrapper header` (for a function template `add 'template ... NAME<...>(...);'`), `template specialization X is not instantiated; add 'template struct X<...>;' to a wrapper header`, `partial template specializations are not supported`, `member templates are not bound`, `ambiguous template arguments`;
- standard library: `std::X is not supported` for any `std::` type other than the shims above (`shared_ptr`, `map`, `function`, `optional`, iterators, streams, non-`const` `std::string&` and `std::vector<T>&` parameters), and `std::string& result is not supported`, `std::vector<int>& result is not supported` for non-`const` references in results;
- macros: `function-like macro`, `empty macro`, `not a constant`.

Private and protected members and deleted functions that are not members are ignored without a message, and `using namespace` and namespace aliases produce no bindings.

### Validation

The ABI fuzzer (`tests/abi/fuzz/fuzz.py`) runs C and Zark against each other with independently computed checksums: on Linux x86-64 with the native and both LLVM backends, on arm64 (Linux and Apple) with the LLVM backends. Its IR oracle (`--ir-oracle aarch64,arm64-apple`) compares, for every generated signature, the `extern` declaration, the direct and indirect call, the `export` thunk and the function pointer target that `zark ir --arch aarch64` emits with what `clang --target=aarch64-linux-gnu` and `--target=arm64-apple-macosx` emit for the same C: parameter and result types and the `sret`, `byval`, `signext`, `zeroext`, `inreg` and `alignstack` attributes. `tests/run.sh` runs it on Linux x86-64, so the arm64 classification is checked on every x86-64 run and executed only on arm64 hosts (CI). `zark cbind --arch aarch64` is checked against the arm64 golden files in `tests/cbind/*.a64.*`.

## 9. System (prelude)

| Area | Functions |
|---|---|
| Files | `read_file(a, path) !str`, `write_file(path, data) !void`, `file_exists(path)` |
| Processes | `!i32 run(a, str[] argv)` (fork/execvp/waitpid; returns the exit code), `env(name) !str`, `arg_count()`, `arg(i)` |
| C strings | `!u8* to_cstr(buf, s)` (no allocation), `!u8* a.dupz(s)`, `cstr(p) str` |
| Numbers | `parse_int`, `parse_int_radix(s, radix) !u64` (radix 0 = auto 0x/0b/0o), `parse_float`, `bits_f64`, `f64_from_bits` |
| Strings | `str_find`, `str_find_byte`, `str_rfind_byte`, `str_trim`, `str_starts_with`, `str_ends_with`, `is_digit/is_alpha/is_alnum/is_hex/is_upper` |

## 10. Not in v0.6 (deliberately)

Heap-allocated closures, operator overloading, exceptions, a GC, implicit copies through a heap, inheritance, and macros.

Candidates for later: `comptime` blocks, `inline for`, and `@cImport`.

## 11. Limits of the checks

The ownership, borrow and async checks follow variable names and field paths rooted in a local; they are not a proof. These cases are accepted and are the caller's responsibility (each has a tracking issue):

- a pointer stored inside another struct: using it after the container is consumed or reallocated is not detected (#57);
- `auto x = *p;` on a non-trivial C++ object is a bitwise copy C++ does not know about (#59);
- data races between threads sharing a pointer, a `List` or a `Map` are not checked (#60);
- an `extern fn` pointer, a closure stored in a struct, or a pointer returned from a `borrows` method then passed through an integer loses its origin: only the direct cases in section 7 are tracked;
- `str` equality is an inline `memcmp`; strings with interior NULs compare correctly but are not C strings, and `to_cstr` rejects embedded NULs.

Run `zark fmt` and the tests in `tests/errors` for the diagnostics that *are* enforced; a rejected valid program is a bug, an accepted invalid one is a soundness hole to report.

## 12. Undefined and implementation-defined behaviour

- `--release`, `--fast` and `--freestanding` remove integer overflow, bounds and division-by-zero checks. In those modes overflow wraps (two's complement), an out-of-bounds index is undefined behaviour, and division by zero is undefined behaviour. Safe builds panic with `__ovf`, `__oob`, `__oobs` and `__divz`.
- Argument evaluation order is not specified; do not rely on side effects in argument lists. `defer` and `errdefer` run in reverse registration order (LIFO); `errdefer` runs on an error return and on cancellation.
- `as` between integers wraps to the target width; `float as int` truncates toward zero; a float-to-integer cast of a value outside the target range is undefined behaviour; `f64 as f32` rounds to nearest even.
- A union is the C struct `{ i32 tag; _Alignas(8) union { ... } payload; }`; `tag` is the zero-based variant index. Reading a variant other than the active one, or matching a tag that no arm covers when the check is bypassed, is undefined.
- Struct layout and alignment follow the C ABI of the target (section 8). Padding bytes are not guaranteed to be zero after a copy; field initializers zero the fields, not the padding.
- Casting a pointer to an integer and back is only defined for the same address space and provenance; the compiler does not track provenance. Dereferencing a pointer with insufficient alignment is undefined.
- Pointer values printed with `{}` are addresses; they differ between runs and builds, so do not use them as program output in tests.
- The native backend and the LLVM backend share the frontend and are checked against each other by `tools/fuzz_prog.py`; where they disagree, that is a bug, not an allowed difference.
