---
title: Debugging and reading errors
order: 42.5
section: Reference
description: How to read the compiler's messages, what each kind of panic means, and how to find a bug with tests, prints, gdb and the debugging allocator
---

Most of the time with a new language goes into reading what it tells you. This page teaches that: how a message is built, the messages you will meet most often with the fix for each, and what to do when the program compiles and still does the wrong thing.

## How an error message is built

```zark error
void main() {
    const auto total = 10;
    println(totl);
}
```

1. **Where:** file and line, then the severity.
2. **What:** one sentence. Names in single quotes are names from your code.
3. **The line itself**, and under it a caret `^` at the expression the message is about.
4. **A suggestion** when the compiler can guess ("did you mean ...").

Read the first message first. The compiler stops a function at its first problem, so later messages often disappear once the first is fixed.

## Common compile errors and their fixes

A type does not fit. The compiler does not narrow or change sign by itself:

```zark error
void main() {
    const i64 big = 1000;
    const i32 small = big;
    println(small);
}
```

Fix: write `big as i32` if losing bits is acceptable, or use the wider type.

A function does not always return:

```zark error
i64 sign(i64 x) {
    if (x < 0) { return -1; }
    if (x > 0) { return 1; }
}

void main() { println(sign(5)); }
```

Fix: add the `return 0;` for the remaining case.

A forgotten error:

```zark error
!i64 parse(str s) { return parse_int(s); }

void main() {
    parse("12");
}
```

Fix: `parse("12")?` in a function that returns `!T`, `catch` with a fallback, or `_ = parse("12") catch 0;` if you really want to ignore it.

A `match` that is missing a case:

```zark error
enum Dir { North, South, East, West }

str name(Dir d) {
    return match d {
        .North => "n",
        .South => "s",
        .East => "e",
    }
}

void main() { println(name(.West)); }
```

Fix: add `.West` (this is the check that makes adding a variant safe).

A struct that does not satisfy an interface:

```zark error
interface Shape { f64 area(); f64 perimeter(); }

struct Square {
    f64 side;
    f64 area() { return this->side * this->side; }
}

void main() {
    auto s = Square{ .side = 2.0 };
    Shape sh = &s;
    println(sh.area());
}
```

Fix: implement the missing method.

A string with braces:

```zark error
void main() {
    println("{"a": 1, "b": 2}");
}
```

Fix: a literal brace is written twice, `"{{\"a\": 1, \"b\": 2}}"`. Interpolation is `{expression}` or `{expression:format}`.

## Ownership messages

These come from the checks described in [the safety model](safety.md). They always name two lines: where the thing stopped being valid, and where you used it.

```zark error
void main() {
    const auto a = c_allocator();
    auto buf = a.alloc<u8>(16) catch return;
    a.free(buf);
    buf[0] = 1;
}
```

`'buf' is used after 'free' consumed it`: the line above is the `free`. Either remove the later use, move the `free` to after the last use, or give the variable a new value first.

```zark error
void main() {
    auto l = List<i64>::init(c_allocator());
    defer l.deinit();
    l.push(1) catch return;
    const auto view = l.slice();
    l.push(2) catch return;
    println(view.len);
}
```

`'view' points into 'l', and 'push' ... may have moved or freed that memory`: take `view` again after the `push`.

```zark error
i64* make() {
    i64 local = 5;
    return &local;
}

void main() { println(*make()); }
```

`returning something that points into local`: the local dies when the function returns. Return the value, let the caller pass in the storage, or allocate with an allocator.

## What a panic tells you

A panic is a bug in the program. The message has the reason and the place:

| Message | Meaning | Look for |
|---|---|---|
| `index 3 out of bounds (len 3)` | an index past the end | an off-by-one, a loop to `len` instead of `len - 1` |
| `slice [2..9] out of bounds (len 5)` | a slice range that does not fit | the arithmetic of the range |
| `division by zero` | a divisor that is zero | a missing check before `/` or `%` |
| `integer overflow` | a result that does not fit its type | a type that is too small, or `+%` was meant |
| `assertion failed` | an `assert` that was false | the condition and the data that reached it |

Run the failing case again under `-g` and `gdb` to see the variables.

```text
$ zark build -g crash.zk -o crash
$ gdb ./crash
(gdb) break crash.zk:12
(gdb) run
(gdb) print total
(gdb) bt
```

`-g` adds line numbers, local variables, structs and arrays to the debug information. Breakpoints by `file:line` work.

## The program is wrong but nothing fails

1. **Print the data.** `println` prints a struct with its field names and a slice with its elements. Print before and after the step you suspect.
2. **Write a test that fails.** Put the smallest input that shows the problem in a `test` block, run `zark test file.zk`, and fix until it is green. The test stays as protection.
3. **Shrink the input.** Remove code and data until the problem is still there and nothing else is. The cause is usually visible at that point.
4. **Ask a different backend.** `zark run file.zk`, then `zark run file.zk --llvm` and `-O`. In the safe mode all of them must print the same. If they do not, you have found a compiler bug; save the file.

## Memory problems

If the program crashes with a segmentation fault, or a result changes from run to run, assume memory first.

1. Run it with the crash handler (it is on by default). The reason line says `null pointer`, `stack overflow` or `use after free`.
2. Change the allocator in the failing path to a `DebugAllocator` (`DebugAllocator::init()` and `dbg.allocator()`). A use after free, even through a copy, stops at the exact access and names the block. `dbg.deinit()?` reports blocks that were never freed.
3. If a block number is reported, set `dbg.trap_id` to it and run under `gdb`: the program stops where the block was allocated.

## When it is slow

```text
$ zark run app.zk --time
time: frontend 12.0 ms, native backend 4.1 ms, link 18.3 ms
```

That is the compiler's time. For the program's own, build with `-O` (optimized and still safe). If it is still too slow and tested, `--release` removes the checks. Measure before and after: do not guess.

## Looking inside the compiler

| Command | Shows |
|---|---|
| `zark tokens file.zk` | the tokens after the lexer |
| `zark ir file.zk` | the LLVM IR that the compiler generates |
| `zark fmt file.zk` | nothing: it rewrites the file with the standard formatting (use `--check` to only test) |

When you report a compiler bug, include the smallest file that shows it, the command you ran, and the output.

## What next

- The list of what is checked: [the safety model](safety.md).
- The questions that people ask first: [pitfalls and FAQ](gotchas.md).
