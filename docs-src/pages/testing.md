---
title: Testing
order: 31
section: Interop and tools
description: test blocks, assert, zark test, how to test errors and memory, and organizing tests in Zark
---

Tests are built into the language: a special `test` block is written next to the code, and the command `zark test` runs them. No separate libraries or configuration files are needed.

## The first test

```zark test
i64 add(i64 a, i64 b) {
    return a + b;
}

test "adds" {
    assert(add(2, 3) == 5);
}

test "zero is neutral" {
    assert(add(7, 0) == 7);
}
```

Run it with the command:

```sh
zark test main.zk
```

`test "name" { ... }` is a top-level declaration. Inside is ordinary code. A test is a function that returns `!void`, so `?` works in it.

A test **passes** if the block reaches its end. It **fails** if an `assert` or `panic` fires, or if `?` receives an error.

## What `zark test` does

1. Compiles the file with all the `test` blocks (and with all its imports).
2. Runs each test **in a separate process**. The failure of one (even a crash) does not break the others.
3. Prints `ok` or `FAIL` for each and a summary.
4. For failed tests, shows everything they printed.
5. Returns exit code 0 if nothing failed, and 1 if something did.

`test` blocks are **ignored** by `zark run` and `zark build`. A file with tests remains an ordinary program.

## What failures look like

```zark test fails
i64 add(i64 a, i64 b) { return a + b; }
!i64 parse(str s) { return parse_int(s); }

test "passes" {
    assert(add(1, 2) == 3);
}

test "error through ?" {
    const auto n = parse("zz")?;
    assert(n == 0);
}

test "false assertion" {
    assert(add(1, 1) == 3);
}

test "panic" {
    panic("failed: {1 + 1}");
}

test "output is shown only for a failed test" {
    println("this line will not be shown");
    assert(true);
}
```

Each failure shows its reason:

- `error: Name`: `?` propagated an error;
- `assertion failed (file:line)`: the condition in `assert` is false;
- `panic: message (file:line)`: `panic` was called.

The output of **passed** tests is hidden: it is needed only when something is broken.

## `assert`

`assert(condition)` checks a `bool`. If the condition is false, the program ends with a message and a location. It works not only in tests but in ordinary code too:

```zark run panic
void main() {
    const auto xs = [1, 2, 3];
    assert(xs.len == 3);
    println("the first assertion held");
    assert(xs[0] == 2);
    println("we will not get here");
}
```

`assert` has no separate message. If you need context, use `panic` with a format:

```zark run panic
void main() {
    const auto got = 41;
    if (got != 42) {
        panic("expected 42, got {got}");
    }
}
```

## Testing errors

An expected error is checked with `catch`:

```zark test
!i64 parse(str s) {
    if (s.len == 0) { return error.Empty; }
    return parse_int(s);
}

test "an empty string is the Empty error" {
    const auto r = parse("") catch |e| {
        assert(e == error.Empty);
        return;
    };
    assert(false);
}

test "an invalid number" {
    const auto r = parse("x") catch |e| {
        assert(e == error.InvalidNumber);
        return;
    };
    assert(false);
}

test "a valid number" {
    const auto n = parse(" 42 ")?;
    assert(n == 42);
}
```

The pattern is this: `catch |e|` checks the error and leaves the test through `return`. If there was no error, control reaches `assert(false)` and the test fails.

## Testing with memory

Tests can allocate memory like ordinary code. Create an allocator inside the test and free through `defer`:

```zark test
test "list" {
    auto xs = List<i64>::init(c_allocator());
    defer xs.deinit();
    xs.push(1)?;
    xs.push(2)?;
    assert(xs.len == 2);
    assert(xs.get(1) == 2);
}

test "arena and strings" {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();
    const auto s = a.dup("hello")?;
    assert(s == "hello");
}

test "running out of memory is an ordinary error" {
    u8[16] mem;
    auto fb = FixedBuf::init(mem[..]);
    const auto a = fb.allocator();
    _ = a.alloc<u8>(10)?;
    const auto r = a.alloc<u8>(10) catch |e| {
        assert(e == error.OutOfMemory);
        return;
    };
    assert(false);
}
```

The last test shows the advantage of explicit allocators: the behavior when memory runs out is checked deterministically, with no hacks.

## Organization

Tests are usually written **in the same file**, under the code they check: then nothing needs to be imported.

If there are many tests, create a separate file and import the module:

```zark file=mathx.zk
i64 clamp(i64 x, i64 lo, i64 hi) {
    if (x < lo) { return lo; }
    if (x > hi) { return hi; }
    return x;
}
```

```zark test
import "mathx.zk" as m;

test "clamp inside the range" {
    assert(m::clamp(5, 0, 10) == 5);
}

test "clamp cuts off the edges" {
    assert(m::clamp(-3, 0, 10) == 0);
    assert(m::clamp(30, 0, 10) == 10);
}
```

Only the tests of **the file you specified** are run. The `test` blocks of imported files are not run.

Test names may repeat (the compiler does not check), but it is better if they are unique: you find the failed test by its name.

## A file without tests

If a file has no `test` blocks at all, the command reports `0 passed, 0 failed` and exits with code 0. Do not confuse this with "all tests passed".

## Running from an editor and in CI

- In VS Code / code-oss the extension shows a run button above every `test` (see [tooling](tooling.md#language-server-and-editor)).
- In CI one command is enough: `zark test main.zk`. Exit code 1 means a failure.
- The optimization mode can be switched: `zark test main.zk -O` runs the same tests through LLVM `-O2`. Useful for making sure optimizations do not change the behavior.

## What next

- Failing tests often come down to errors: [errors and optional values](errors-and-optionals.md).
- How the compiler's own test suite is organized: [how it all works](how-it-works.md).
