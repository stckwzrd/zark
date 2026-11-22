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
- `sizeof(T)` and `alignof(T)` are compile-time `u64` values. The operand may also be an expression (`sizeof(x)`, `sizeof(f())`); it is not evaluated.
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

The compiler itself knows only these names: `sizeof`, `alignof`, `embed`, `panic`, `assert`, the type `Fmt`, `Self`, `error`, `Option` (the meaning of `?T`), `async` and `await` (syntax only), the prelude types `Poll` and `Context` (the types used by the generated `poll` of an async function, see section 7b), the method name `poll` and the variant names `Ready` and `Pending` of `Poll` (used by `await`, the generated `poll` and the inference of section 7b) and the runtime helpers `__panic`, `__oob`, `__ovf`, `__str_eq`, `__errname`, `__rt_init` (called first by `main` and by the test runner unless `--freestanding`; the prelude uses it to install the crash handler). Everything else is ordinary code in `std/std.vibe`.

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
- `align(N) T name = v;` before a global variable aligns it to `N` bytes (a power of two, page tables and DMA buffers). `align(N) struct S { ... }` aligns the struct (and every variable, array element and field of that type) to `N` bytes and pads its size to a multiple of `N`; the native backend supports locals up to 16 and switches to LLVM for more.
- `asm<R>("template", "constraints", args...)` (`R` defaults to `void`): LLVM inline asm with `sideeffect`. Braces in the strings are written `\{` and `\}`. The native backend encodes the templates used by the prelude (`Cpu`, `Port`, `Atomic`) and rejects others with a message; `--llvm` accepts any.
- `a +% b`, `a -% b`, `a *% b` are integer operators that always wrap (same precedence as `+` `-` and `*`); they are never checked by `--check-overflow` and never get `nsw` under `--fast`.
- SIMD vectors: `f32x4`, `i32x8`, `u8x16`, ... (element type `i8..i64`, `u8..u64`, `f32`, `f64`; 2, 4, 8, 16 or 32 lanes; at most 32 bytes) are LLVM vectors. `T(a, b, ...)` builds one, `T(x)` splats; `+ - * /`, `& | ^` and unary `-` work per lane (a scalar operand is splatted), `v[i]` reads and writes a lane, comparisons are not defined. A program that uses them is built through LLVM.
- `+`, `-` and `*` on integers in user code panic on overflow (`__ovf`) in a safe build; `--release`, `--fast` and `--freestanding` remove the check and they wrap, unless `--check-overflow` is given.
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

Ownership: a parameter written `move T x`, or a method written `R name(...) move { ... }` (which consumes `this`), takes the argument over. When the argument is a plain local variable or parameter, the compiler rejects any later use of that variable until it is assigned again. The state is merged over `if`, `match`, `catch` and loops (a variable consumed in a loop body must be reassigned or left through `break`/`return`). `defer` and `errdefer` bodies are checked where they run. The check follows variable names only: copies of a pointer and field paths are not tracked. `move` is contextual, not a keyword. The prelude marks `Allocator.free`, `Allocator.destroy` and the `deinit`/`close`/`join` methods.

Borrows: a method written `R name(...) borrows { ... }` returns a pointer or slice into the receiver, and one written `invalidates` may move or free what earlier pointers refer to. When a local variable is initialized or assigned from a call to a `borrows` method of a local variable `c`, from `&c.f`, `&c[i]` or `c[a..b]` with `c` a pointer or slice, any later use of that variable after `c` was consumed or after an `invalidates` call on `c` is an error. A pointer or slice into a local array or struct value (`&x`, `&x.f`, `&a[i]`, `a[lo..hi]`) cannot be returned, and cannot be stored through a pointer parameter or into a global. The prelude marks `List.push/append/insert/reserve`, `Map.put/remove` as `invalidates` and `List.at/slice`, `Map.get_ptr` as `borrows`. Like `move`, both words are contextual.

A loop `for (T x : seq)` whose `seq` is a `borrows` call, a container variable or field path (`list`, `this->items`), or a variable that holds a borrow, may not reach its next iteration after an `invalidates` call on that container; `break` and `return` after the call are fine. Borrows and `invalidates` calls follow field paths rooted at a local variable (`this->items`, `s.list`), not only plain variables.

A struct declared `owned struct S { ... }` is a resource that must be consumed. A local variable of such a type that is initialized from a call (not from a struct literal) must, on every exit of its scope, including the exits taken by `?` and by `break`/`continue`, have been passed to a `move` parameter or `move` method, passed or assigned elsewhere as a value, or returned. Dropping a value of such a type (`f();` or `_ = f();`) is an error. A variable initialized by a call that takes a closure capturing locals, or the address of a local, counts as pointing into those locals: it cannot be returned or stored through a pointer parameter. The prelude declares `Thread` `owned`, with `join` and `detach` as `move` methods. `owned` is contextual.

## 7a. Compile-time evaluation

`comptime EXPR` (a prefix operator, binding like unary `-`) evaluates `EXPR` while compiling and uses the result as a constant. The compiler builds the program with a generated `main` that runs `EXPR` (all functions, constants and the prelude are available; local variables and type parameters are not), runs it, and reads the bytes back. The type must be plain data: integers, floats, `bool`, enums, `str`, and arrays or structs of those; a `void` expression is run for its effects. A result of an array or struct type lives in read-only data and is indexed in place. A top-level `comptime EXPR;` runs before code generation, so `comptime assert(sizeof(T) == 16);` is a static assertion. Each distinct expression is run once per compilation, in a child compilation of the same program. `comptime` inside a string interpolation is not supported. The prelude helpers `__ct_emit` and `__ct_emit_str` carry the result.

## 7b. Async

`async` is a contextual modifier written before the return type of a function, a method or a generic function: `async i64 f(i64 a)`, `async !str fetch(Conn* c)`, `static async i64 make()`, `template<T> async T id(T v)`. `await` is a contextual prefix operator. Both words stay ordinary identifiers elsewhere. `async` on an `extern` or `export` function is an error.

```vibe
async !str fetch(Conn* c, str path) {
    c.write_all("GET {path}\n")?;
    auto line = await c.read_line();
    return line;
}
```

**Frames.** Calling an async function does not run it. It returns its frame by value, in state 0: a struct made by the compiler (one per function and per generic instance) with the state number, the copied arguments, the result slot, every local and compiler temporary of the body, and the frames of the futures it awaits. So `auto f = fetch(c, "/");` works and `sizeof(f)` is the size of the frame; `sizeof(fetch(c, "/"))` gives it without running anything. For a method, `this` is an argument like any other (a pointer, not a copy).

**The `poll` protocol.** The frame has a method `Poll<T> poll(Context* cx)`. `Poll<T>` is the prelude union `{ T Ready; Pending; }`, `Context` holds a `Waker { void* data; fn(void*) wake_fn; }`. Any struct with a method of that shape is a future, so a library writes leaf futures by hand and `await` treats them like frames. An async function without a result type is a future of `Poll<bool>` that yields `true`. The executor polls a task again only after its waker was called, so a future that returns `Pending` must have arranged for that. `await e` on a type without such a method is an error.

**`await e`.** It evaluates `e`, stores the future in the frame, and polls it with the same `cx`. If it is pending, the current `poll` returns `Pending` and the next `poll` resumes at the same place. On `Ready(v)` the expression is `v`. `return` and `?` in an async function store the result in the frame and return `Ready`. `defer` and `errdefer` run at the usual places, once per exit.

**Where `await` may appear.** Nothing computed earlier in the same expression may be alive across a suspension, so `await` is accepted only in these positions, optionally followed by `?` or `catch`:
- as a whole expression statement: `await f();`
- as the initializer of a declaration: `auto v = await f();`
- as the right side of `=` to a local variable: `v = await f();`
- as the operand of `return`: `return await f();`
- as the whole condition or scrutinee of `if`, `while` or `match`: `if (await ready())`, `while (await more())`, `match (await next()) { ... }`. A `while` condition is awaited again on every iteration.

Anything else is rejected with "bind the result to a variable first": an argument, an operand (`await f() == 2`, `(await f()) as i64`), `p.f = await e`, `a[i] = await e`, `x += await e`, an `await` inside a `catch |e| { ... }` block or inside a block arm of a `match` expression that is part of a larger expression (`auto v = g() catch |e| { await h(); 1; };`). `await` is also an error in `defer` and `errdefer` (also in a block), in a closure, and outside an async function. The statement forms `if`, `while`, `match`, `for` and plain blocks may contain `await` in their bodies as usual.

**Recursion.** A frame cannot contain itself. A call chain that would (an async function awaiting itself, or a cycle through several) is an error that says the recursive call has to go through a pointer to a separately allocated frame.

**Pinning and ownership.** Once polled, a frame holds pointers into itself (locals whose address was taken, the awaited child frame), so it must not move. The compiler checks what it can see by name: `await f` consumes the local variable `f` (a later use is the "used after consumed" error of section 7), and so does passing it to a `move` parameter such as the executor's `spawn(move F fut)`. A future that was not started may be moved freely. A future reached through a pointer, a field or an array element is not consumed by name (`await h.y;` twice compiles), and moving a frame after it was polled is not detected: that is up to the library and the caller.

**Borrows across `await`.** The executor may run other tasks while one waits, so an `await` counts like a call that `invalidates` every container borrow: a local pointer or slice that came from a `borrows` method (`list.at(i)`, `list.slice()`), and the iteration `for (x : c)` over a container whose `slice()` is a `borrows` method, may not be used after the `await` (a loop must not reach its next iteration). The pointer has to be taken again after the `await`. The limits are the ones of `invalidates` (section 7): names only; `&l.items[0]`, pointers derived from a copy of a borrowed slice, and pointers stored in structs are not tracked; a pointer passed into an awaited call lives in that child frame and is not tracked either. Pointers to the frame's own locals and slices of the arguments are fine across an `await`. The rule also applies to a `List` that is local to the async function, where nobody else could touch it.

**Cancellation.** There are no destructors: a frame that is dropped while suspended does not run its `defer`s and its awaited child frames are not finished. Pending I/O that belongs to a dropped future has to be disarmed with its `cancel()` (`Readable`, `Writable`, `Accept`, `Read`, `Write`). Without it the registration stays with the executor until the task ends (for the future passed to `block_on`, until `block_on` returns): when the descriptor becomes ready, the task is woken once more and the descriptor is then left out of the poller, so the executor does not spin, but the registration still counts as pending I/O, so a task that then waits for something that never comes blocks the executor instead of getting `error.Deadlock`. `cancel()` only disarms the registration its own future made: if another future armed the same descriptor and direction after it, that one stays armed.

**The library (`std/async`).** The module is plain Vibe plus a small poller in `std/rt.c` (`vrt_poller_*`: epoll on Linux, kqueue on macOS; there is no Windows reactor). It is single-threaded and uses the `Allocator` given to the executor, nothing else allocates.
- `Executor::init(a)` / `deinit()` (an `owned` struct). Tasks keep a pointer to it, so it must not move after the first `spawn`.
- `ex.spawn(fut)` takes a future by `move`, puts it in memory from the executor's allocator and returns `JoinHandle<T>`; spawned tasks run while some `block_on` is running. `ex.block_on(&fut)` polls a future and the executor until the future is ready, and returns `error.Deadlock` if nothing can make progress. `JoinHandle<T>` has `done()`, `take()`, `detach()` and is itself a future (`await h`). A handle is used up once its result was taken (by `take()`, by awaiting it or by `block_on(&h)`) or it was detached; any later use of it or of a copy of it panics, and so does `take()` before `done()`.
- The result type of `spawn` and `block_on` is inferred: when a call to a generic function leaves exactly one type parameter unknown and exactly one of the known type arguments is a struct whose `poll` returns `Poll<X>`, the unknown parameter becomes `X`. So `auto h = ex.spawn(chain())?;` and `auto r = ex.block_on(&f)?;` need no annotation, for async frames and hand-written futures alike. An annotation such as `async::JoinHandle<i64> h = ex.spawn(f)?;` or `i64 r = ex.block_on(&f)?;` still works and is checked; explicit type arguments (`ex.block_on<Countdown, i64>(&f)`) are needed only when the future's `poll` is itself generic. For a future whose result is itself an error union `!X`, the inferred result of `block_on` is `!!X` (unwrap both with `??`), while the annotation `X r = ex.block_on(&f)?;` merges the two.
- `Sleep::after(&ex, ms)` is a future that is ready after `ms` milliseconds; `Readable::on(&ex, fd)` and `Writable::on(&ex, fd)` are ready when the descriptor is.
- `TcpListener::bind(&ex, host, port)` has `accept()`; `TcpStream` has `read(buf)` and `write(data)`; these return futures of `!TcpStream`, `!i64` (0 means the peer closed) and `!i64` (the byte count, all of `data` is written). `TcpStream::connect(&ex, host, port)` is a blocking call that returns a nonblocking stream. `close()` consumes the listener or the stream.
- One waker is kept per descriptor and direction.

## 8. C interop

- `extern` declares a C function and `export` defines one.
- `void*` is C's `void*`. String literals pass as `u8*` (they are NUL-terminated). Any other `str` must be passed as `s.ptr` explicitly.
- C varargs follow the usual promotions; slices are rejected.
- Structs (and slices) are passed to and returned from `extern` functions by value following the System V x86-64 ABI: up to 16 bytes in registers by eightbyte class (INTEGER or SSE), larger or when the registers run out on the stack (`byval`), large results through a hidden pointer (`sret`). `export` functions and function pointers called from C take aggregates by pointer.
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
