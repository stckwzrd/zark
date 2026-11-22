# async, await and a scheduler in the language

## Intent

Vibe gets cooperative concurrency as a base layer of the language, the way Rust has it, so that a Tokio-like library (timers, sockets, HTTP, channels, `select`) can be written in Vibe on top. The owner wants it for the general growth of the language: backends first, but anything that waits (servers, clients, tools, later maybe embedded) should be able to use it. It follows the language's own rules: no hidden allocations, explicit `Allocator`, the compiler does not know std names except a short protocol list.

## Goals

- `async` functions and `await`, compiled by the compiler into a state machine whose size is known at compile time. The caller decides where the state lives (stack, parent state, arena, heap).
- A scheduler and an I/O reactor shipped with the compiler (`std/async` plus a small C part in `std/rt.c`): a single-threaded executor in this project.
- The same behavior on the native and the LLVM backend, and on Linux and macOS (epoll and kqueue). The lowering produces ordinary IR, so neither backend gets new instructions.
- Misuse is a compile error where the existing ownership checks can see it: awaiting a future twice, moving a future after it was started, an `await` in a position the lowering cannot handle.

## Non-goals and anti-goals

- No stackful coroutines or green threads. No hidden allocation per task or per call.
- No Windows reactor (IOCP) in the first version.
- The library (async net, http, fs, channels, `join`/`select`) is not part of the language work. The first milestone only needs a timer and a TCP socket to prove the base.
- Anti-goal: an `async` that works but forces a heap allocation for every future, or a borrow story that silently allows dangling pointers into a moved state.

## Approaches considered

- A. State machine in the compiler (chosen by the owner). Size known statically, no hidden allocation, free on both backends because it is IR, closest to Tokio. Cost: the biggest compiler change, plus rules for pointers into the state.
- B. Stackful coroutines (own stack per task, context switch in asm). Cheap to build, but task size is not visible, needs asm per architecture, and it is not the Tokio model.
- C. B first, A later. Fast scheduler, but two models and a second migration.

## Design

### Surface syntax (the builder may refine)

```
async !str fetch(Conn* c, str path) {
    c.write_all("GET {path}\n")?;      // ordinary calls stay ordinary
    auto line = await c.read_line();   // suspension point
    return line;
}
```

- `async` is a contextual modifier before the return type of a function or method, like `static`. `await` is a contextual prefix operator.
- Calling an async function does not run it. It returns its frame: a compiler-generated struct (one per function and per generic instance) holding the state number, the copied arguments, all locals, the result slot and the frames of the futures it awaits. The frame is an ordinary value, so `auto f = fetch(c, "/");` works and its size is `sizeof(f)`.
- The generated poll function has the shape `Poll<T> poll(Frame* f, Context* cx)`. `Poll<T>` is a std union `{ Pending, Ready(T) }`. Any struct with a method of that shape is a future, so std can write leaf futures (timer, socket read) by hand and the executor treats them the same.
- `await e` takes the future `e` by `move`, stores it as a field of the current frame, polls it with the same `cx`, and returns `Pending` from the current poll if the child is pending. On `Ready(v)` the expression yields `v`.
- `return` and `?` inside an async function store the result in the frame, set the state to done and return `Ready`.

### Lowering (in `gen`, as IR text)

1. All locals of an async function become fields of the frame (no allocas for them). The IR function is `poll`; it starts with a dispatch on `f.state`, written as an `icmp`/`br` chain because the native backend has no `switch`.
2. Each `await` is a suspension point: store state `k`, poll the child, if pending `ret Pending`; resume label `k` jumps back to the poll. Since locals are in the frame nothing needs saving, and no liveness analysis is needed in the first version.
3. `defer` and `errdefer` already generate inline code at scope exits and keep working, because the frame outlives the suspension.
4. Restriction that makes (2) sound: no SSA temporaries may be live across a suspension, so `await` is only allowed where the expression stack is empty: as the whole expression statement, the initializer of a declaration, the right side of an assignment, the operand of `return`, or the scrutinee of `if`, `while` and `match`, optionally followed by `?` or `catch`. Anywhere else the error message says to bind the result to a variable first. Spilling temporaries is future work.
5. Recursion: a frame that contains itself is the existing "struct contains itself" error (tests/errors/e19); the message for async should say the recursive call has to go through a pointer to a separately allocated frame.

### Pinning and ownership

A frame that has been polled once holds pointers into itself (`&local`, nested frames), so it must never move. The rule, enforced with the existing `move` / `owned` machinery in `gen_move.vibe`: a not-yet-started future is a value that can be moved (stored in a task, passed to `spawn`); `await`, `spawn` and the executor consume it; after that it is only reachable through a pointer. Dropping a suspended frame does not run its `defer`s (Vibe has no destructors). The first version documents this; `cancel()` that resumes a frame into a cancelled state to run its defers is a later addition.

### Protocol names

The compiler learns the names `async`/`await` (keywords), `Poll` and `Context` (the types in the generated `poll`), added to the protocol list in SPEC section 6 and to `tests/no_magic_names.sh`. Everything else is std.

### Scheduler and reactor

- `std/rt.c`: `vrt_poller_*` over epoll (Linux) and kqueue (macOS): create, add/modify/remove fd with read/write interest, wait with timeout, wake from another thread.
- `std/async`: `Executor` (run queue, timer heap, reactor), `block_on(future)`, `spawn(future)` returning a `JoinHandle<T>`, `Waker` stored in `Context`, `sleep(ms)`, async `TcpListener`/`TcpStream`. Tasks live in memory from an `Allocator` given to the executor. A multi-threaded executor on `std/thread` is a later project.

## Build order and milestones

1. Runtime without compiler help: `Poll`, `Context`, `Waker`, `Executor`, reactor, `sleep`, a hand-written future for a socket read, tests, a small echo server. This fixes the protocol.
2. Compiler: `async`/`await` lowering with the position rule, frames, generics, methods, `?`. Tests in `tests/edge` (golden output), `tests/errors` (rejected uses), both backends, determinism of the fixed points.
3. Ownership rules: consumed futures, no move after start, borrows held across `await` (reuse the iteration/borrow records).
Scope (decided by the owner): this project stops after step 3 with a single-threaded executor, a timer and a TCP socket to prove the base. The multi-threaded executor (which needs a rule for what may move between threads) and the library layer (`join`, `select`, channels, async http) are separate later projects.

Each step ends green: both fixed points, `tests/run.sh`, CI on all systems. New syntax goes through the two-step seed rule from CLAUDE.md (teach the compiler first, update the seed, only then use it in `selfhost/`; the compiler itself does not need to use `async`).

## Calls made while writing this down (builder: change them only with a reason)

1. Frame size. `gen` already keeps a `pending` list of function bodies and prints all type definitions first (`types_out`). When a call site needs the frame type of an async function (`alloca`, `sizeof`, a field of a parent frame), `gen` generates that function's body at that moment, nested, with its state saved and restored, and completes the frame struct afterwards. A cycle (mutual or self recursion) is the "contains itself" error. This is "extend gen", not a separate type-inference pre-pass. All allocas of an async body go into the frame, including compiler temporaries (match slots, loop iterators).
2. Recognizing a future. `await e` does a structural check: the type of `e` has a method `poll(Context*)` returning `Poll<T>`, the same way `fmt` and iteration are found by method name today. `Poll<T>` and `Context` are declared in the prelude (`std/std.vibe`, a few lines), so the compiler can name them without module prefixes. Generic code is checked at instantiation, like other templates.
3. Erased tasks. `spawn<F>(F fut)` is generic: instantiating it generates a thunk `bool poll_thunk(void* frame, Context* cx)` that polls `F` and, on `Ready(v)`, stores `v` in the result slot that lives in the task memory next to the frame. The executor only sees a task header `{ frame, poll_thunk, state }`, so it needs plain function pointers, not closures. The generated `poll` of a frame is an ordinary function that can be addressed.
4. "Started" and "must not move". The compiler enforces only what it can see: `await` and `spawn` consume the future by `move` (a name used twice is the existing double-move error). Hand-written leaf futures polled through `&f` are library code and documented. At an `await`, any outstanding pointer into a `List` or `Map` that is used later is an error, as if the await were a call that invalidates everything, because another task may run meanwhile. A future that never completes is accepted silently and its `defer`s do not run; this is documented, with `cancel()` as a later addition.
5. macOS is LLVM-only, so "both backends" is tested on Linux and the reactor on macOS is tested through CI with the LLVM backend.

## Constraints

- No new IR instructions; native backend limits (no `switch`, alignment up to 16) apply.
- Safe builds keep overflow and bounds checks inside generated code.
- The generated names and layouts must be deterministic (fixed point native2 == native3).
- Frame size is a normal struct size: it shows in `sizeof` and in errors.

## Left to the builder

- Exact keyword placement for methods and generic async functions.
- Whether `Context` is passed as a hidden parameter or stored in the frame.
- The name and shape of the waker, the timer data structure, kqueue/epoll edge cases.
- How `await` on a call expression builds the child frame in place (avoid a copy).
- Error message wording and the exact set of rejected positions beyond the rule above.

## As built

What was implemented differs from the text above in these points. SPEC.md section 7b describes the language as it is.

- Position rule (design, Lowering item 4). Narrowed: an assignment is accepted only when the target is a plain local variable (`v = await f();`). `p.f = await e`, `a[i] = await e` and `x += await e` are rejected, because the address of the target would be a temporary live across the suspension. The same applies to every `await` that sits inside a larger expression, including one inside a `catch |e| { ... }` block or a block arm of a `match` expression that is itself part of an expression (a counter of expression nesting decides, so even `auto v = f() catch |e| { await g(); 1; };` is rejected). The accepted positions are the expression statement, the declaration initializer, `v = await e`, the `return` operand, and the whole condition or scrutinee of `if`, `while` and `match`, each optionally under `?` or `catch`. The parser turns `await f()?` into `Try(Await(f()))`.
- Further rejections: `await` in `defer` and `errdefer` (also in a block; it is checked where the deferred code is expanded, so an `errdefer` on a path that never exists is not reported), in a closure, and outside an async function. A recursive call chain is an error naming the closing edge ('b' calls 'a', which is already being built).
- Unit results. An async function with no result type is a future of `Poll<bool>` that yields `true`; `Poll<T>` is the prelude union `{ T Ready; Pending; }`.
- `sizeof(expr)` and `alignof(expr)`. The design says the size of a frame is `sizeof(f)`, which needs the expression form (`sizeof(chain())` also works), so the two builtins accept an expression as well as a type. The operand is not evaluated.
- Frames. A frame type is named `<function key>..frame` (the `..` cannot clash with a user name), its fields are state, arguments, result, then every local and temporary in generation order. Calling the function emits an ordinary call that returns the frame by value, and `poll` is registered as a method of the frame, so `fut.poll(&cx)` resolves like a hand-written one. `Context` is the second parameter of `poll`, not a hidden one. Loop bounds, slice bases and lengths, and union match payloads that are used after a suspension are copied into frame slots.
- Task header. `Task.poll_thunk` is a field of closure type `fn[](void*, Context*) -> bool` holding a non-capturing literal made in `spawn<F, T>(move F fut)`, not a plain function pointer. `block_on` takes `F*`, so a future can be polled in place without moving it.
- Timers and I/O. A timer stores a `Waker` (and the task that owns it), not a task pointer. The reactor keeps one `Reg` per fd with a waker for each direction (the later registration replaces the earlier one), and the poller token is the fd. Tasks are freed when they are done, their handle was taken or detached, no timer, registration or joiner still refers to them. `JoinHandle<T>` is itself a future. `Io.cancel()` (also on `Readable`, `Writable`, `Accept`, `Read`, `Write`) disarms pending I/O.
- Ownership. `await` consumes a local variable operand by name, `spawn` takes `move F`. At an `await`, borrows are invalidated only for variables that came from a `borrows` method, and for `for` over a container whose `slice()` is `borrows` (`List` is; a user `slice()` that is not marked is fine). Pointers taken any other way are not tracked (see the limits in SPEC.md 7b). The rule also fires for a container that only this task can reach.
- Not done, as planned: frame cancellation that runs `defer`s, a separate `cancel()` for tasks, an async `connect` (`TcpStream::connect` blocks), macOS testing beyond CI.

