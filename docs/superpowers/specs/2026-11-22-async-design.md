# async, await and a scheduler in the language

## Intent

Vibe gets cooperative concurrency as a base layer of the language, the way Rust has it, so that a Tokio-like library (timers, sockets, HTTP, channels, `select`) can be written in Vibe on top. The owner wants it for the general growth of the language: backends first, but anything that waits (servers, clients, tools, later maybe embedded) should be able to use it. It follows the language's own rules: no hidden allocations, explicit `Allocator`, the compiler does not know std names except a short protocol list.

## Goals

- `async` functions and `await`, compiled by the compiler into a state machine whose size is known at compile time. The caller decides where the state lives (stack, parent state, arena, heap).
- A scheduler and an I/O reactor shipped with the compiler (`std/async` plus a small C part in `std/rt.c`): single-threaded executor first, then a multi-threaded one on `std/thread`.
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
- `std/async`: `Executor` (run queue, timer heap, reactor), `block_on(future)`, `spawn(future)` returning a `JoinHandle<T>`, `Waker` stored in `Context`, `sleep(ms)`, async `TcpListener`/`TcpStream`. Tasks live in memory from an `Allocator` given to the executor. Second step: a multi-threaded executor with one run queue per worker and stealing, built on `std/thread` (`Mutex`, `Cond`, `AtomicI64` exist).

## Build order and milestones

1. Runtime without compiler help: `Poll`, `Context`, `Waker`, `Executor`, reactor, `sleep`, a hand-written future for a socket read, tests, a small echo server. This fixes the protocol.
2. Compiler: `async`/`await` lowering with the position rule, frames, generics, methods, `?`. Tests in `tests/edge` (golden output), `tests/errors` (rejected uses), both backends, determinism of the fixed points.
3. Ownership rules: consumed futures, no move after start, borrows held across `await` (reuse the iteration/borrow records).
4. Multi-threaded executor and a first library layer (`join`, `select`, channel, async http on top of `std/http` pieces).

Each step ends green: both fixed points, `tests/run.sh`, CI on all systems. New syntax goes through the two-step seed rule from CLAUDE.md (teach the compiler first, update the seed, only then use it in `selfhost/`; the compiler itself does not need to use `async`).

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
