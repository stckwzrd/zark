---
title: Async
order: 40.7
section: Reference
description: std/async (futures, Executor, spawn, join, select and cancellation)
---

`std/async` is a single-threaded executor over the runtime poller (`epoll` on Linux,
`kqueue` on macOS). It is plain Zark plus a few `vrt_poller_*` calls; the compiler has no
async-specific code beyond generating the frame of an `async` function.

## A future

A future is any struct with two methods:

```zark
Poll<T> poll(Context* cx);
void cancel();
```

`poll` returns `Ready(value)` or `Pending`. Returning `Pending` is a promise to arrange a
wake-up: either call `cx.waker.wake()` or arm a `Readable`, `Writable` or `Sleep`. A future
that does neither stalls the executor. `cancel()` releases whatever the last `poll` armed;
`spawn` and `block_on` require it, and an `async` function gets it from the compiler.

```zark run
import "std/async" as async;

struct Countdown {
    i64 n;
    void cancel() {}
    Poll<i64> poll(Context* cx) {
        if (this->n == 0) { return .Ready(42); }
        this->n -= 1;
        cx.waker.wake();
        return .Pending;
    }
}

!void main() {
    auto ex = async::Executor::init(c_allocator())?;
    defer ex.deinit();
    auto f = Countdown{ .n = 3 };
    println(ex.block_on<Countdown, i64>(&f)?);
}
```

## Executor, spawn, join, select

`Executor::init(a)` owns the poller and the tasks. `ex.block_on(&f)` drives a future and the
tasks it spawned until the future is ready; it returns `error.Deadlock` when nothing can
make progress. `ex.spawn(f)` takes a future by `move`, stores it in the executor's memory
and returns a `JoinHandle<T>`. The result type of `spawn` and `block_on` is inferred from
the future's `poll`.

```zark run
import "std/async" as async;

struct Ready {
    i64 v;
    void cancel() {}
    Poll<i64> poll(Context* cx) { return .Ready(this->v); }
}

struct Never {
    void cancel() {}
    Poll<i64> poll(Context* cx) { return .Pending; }
}

!void main() {
    auto ex = async::Executor::init(c_allocator())?;
    defer ex.deinit();
    auto a = ex.spawn(Ready{ .v = 20 })?;
    auto b = ex.spawn(Ready{ .v = 22 })?;
    auto j = async::join(a, b);
    const auto p = ex.block_on(&j)?;
    println(p.first + p.second);

    auto s = async::select(ex.spawn(Ready{ .v = 7 })?, ex.spawn(Never{})?);
    const auto r = ex.block_on(&s)?;
    match (r) {
        .First(v) => println(v),
        .Second(_) => println(-1),
    }
}
```

`join(a, b)` yields `Pair<A, B>` when both handles are done. `select(a, b)` yields
`Select2Result<A, B>` from whichever finishes first and cancels the other. A `JoinHandle`
is single-use: `take()` reads the result, `detach()` keeps the task running without a
result, and either one makes the handle invalid. A copy of a used handle panics.

## Async functions and cancellation

An `async` function runs its body up to an `await`, then returns a `Pending` frame.
`await f` polls `f` and suspends the frame. The compiler turns the body into a frame struct
and generates `poll` and `cancel`:

```zark run
import "std/async" as async;

struct Never {
    void cancel() {}
    Poll<bool> poll(Context* cx) { return .Pending; }
}

i64 cleaned = 0;

async !void worker() {
    defer cleaned += 1;
    auto n = Never{};
    await n;
}

!void main() {
    {
        auto ex = async::Executor::init(c_allocator())?;
        defer ex.deinit();
        auto h = ex.spawn(worker())?;
        ex.run_batch();
        println(cleaned);
        h.cancel();
        println(cleaned);
    }
    println(cleaned);
}
```

Cancellation is an unfinished operation, not a normal return: the generated `cancel()` runs
both `defer` and `errdefer` of every scope that is active at the suspension point,
innermost first, cancels the future it was awaiting, and marks the frame finished. It is
idempotent: a second call on the same frame does nothing. `Executor.deinit()` cancels every
live task before freeing it, and each task is cancelled exactly once. `detach()` does not
cancel; the task keeps running.

A `JoinHandle`'s `cancel()` is different from a frame's: it invalidates the handle and
throws away a result that was not taken, so a second call panics, exactly like `take()`.
`select` cancels the losing handle; `join` cancels both sides, except a side that already
produced a value and was taken.

## Channels

`Channel<T>` is an unbounded FIFO between tasks on one executor. `send` never waits; it
only allocates and returns `error.Closed` after `close()`. `recv()` is a future that yields
`!T`, and `error.Closed` when the channel is closed and empty.

```zark run
import "std/async" as async;

async i64 first(async::Channel<i64>* ch) {
    const auto r = await ch.recv();
    return r catch -1;
}

!void main() {
    auto ex = async::Executor::init(c_allocator())?;
    defer ex.deinit();
    auto ch = async::Channel<i64>::init(c_allocator())?;
    defer ch.deinit();
    ch.send(21)?;
    ch.send(22)?;
    auto f = first(&ch);
    println(ex.block_on(&f)?);
}
```

`select_recv(a.recv(), b.recv())` waits for whichever channel is ready first and unregisters
the other one; it yields `.First(v)` or `.Second(v)`, where `v` is `!T`:

```zark
async !i64 pick(async::Channel<i64>* a, async::Channel<i64>* b) {
    const auto r = await async::select_recv(a.recv(), b.recv());
    match (r) {
        .First(v) => return v?,
        .Second(v) => return v?,
    }
}
```

The channel is single-threaded: all its tasks must run on the same executor. `close()` wakes
the receivers; after the queue is drained they get `error.Closed`. Cancelling a suspended
`recv` (via the task or `select_recv`) unregisters its waker, so a later `send` does not wake
a frame that no longer waits.

`std/async` also has `TcpListener`, `TcpStream`, `Readable`, `Writable` and `Sleep`. The
executor is single-threaded: it polls one task at a time. A multithreaded executor and a
channel shared between threads are not implemented yet; `std/thread` has a blocking
`Channel<T>` for that case.
