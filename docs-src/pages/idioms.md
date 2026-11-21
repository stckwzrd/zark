---
title: Writing idiomatic Vibe
order: 20.6
section: Memory and data
description: How to structure Vibe programs: constructors and cleanup, allocators, errors, data modeling, testing and the habits that keep the compiler happy
---

The language lets you write a program in many ways. This page shows the way that works with the compiler's checks instead of against them, and that other Vibe programmers will recognize. Every example here compiles and runs.

## Names and layout

Types are `PascalCase`, functions, methods, variables and fields are `snake_case`, constants are `UPPER_CASE`. Files are `snake_case.vibe`. A function that builds a value is called `init` or `new` (and is `static`), and a function that releases it is `deinit`. Put the types and functions that go together in one file, and import it with `as` when the names might collide ([modules](modules.md)).

## A type that owns memory: `init`, `deinit`, `errdefer`

The pattern is always the same: the constructor takes the allocator, remembers it, and cleans up after itself if a later step fails. The destructor is marked `move`, so using the value afterwards does not compile.

```vibe run
struct Buffer {
    Allocator a;
    u8[] data;
    i64 used;

    static !Buffer init(Allocator a, i64 capacity) {
        const auto data = a.alloc<u8>(capacity)?;
        return Buffer{ .a = a, .data = data };
    }

    void deinit() move {
        this->a.free(this->data);
    }

    !void put(u8 b) {
        if (this->used == this->data.len) { return error.Full; }
        this->data[this->used] = b;
        this->used += 1;
    }

    str text() borrows {
        return this->data[0..this->used];
    }
}

!void main() {
    auto buf = Buffer::init(c_allocator(), 8)?;
    defer buf.deinit();
    for (auto c : "vibe") { buf.put(c)?; }
    println(buf.text());
}
```

Notice three things. The buffer stores the allocator it was created with, so `deinit` needs no argument and cannot free with the wrong one. `text()` is marked `borrows`: a caller that keeps the result and then changes the buffer is told about it. A caller that forgets `deinit` is caught by the `DebugAllocator` in tests.

When a constructor has several steps, each step that allocates gets an `errdefer` that undoes it. It runs only if the function returns an error:

```vibe run
struct Pair {
    i64* left;
    i64* right;
}

!Pair make_pair(Allocator a) {
    const auto left = a.create<i64>()?;
    errdefer a.destroy(left);
    const auto right = a.create<i64>()?;
    return Pair{ .left = left, .right = right };
}

void main() {
    const auto a = c_allocator();
    const auto p = make_pair(a) catch return;
    *p.left = 1;
    *p.right = 2;
    println(*p.left + *p.right);
    a.destroy(p.left);
    a.destroy(p.right);
}
```

If the second allocation fails, the first is freed on the way out. If both succeed, `errdefer` does nothing and the caller owns both.

## Pass the allocator, choose the lifetime

A function that allocates takes an `Allocator` as its first parameter. It does not choose where memory comes from, so the caller can give it an arena, a fixed buffer or a debugging allocator.

Group things that live and die together in one arena. A request, a frame, a compile unit, a test: one arena, one `defer arena.deinit()`.

```vibe run
!str[] split_words(Allocator a, str text) {
    auto out = List<str>::init(a);
    auto start = 0;
    for (auto i : 0..text.len + 1) {
        if (i == text.len || text[i] == ' ') {
            if (i > start) { out.push(text[start..i])?; }
            start = i + 1;
        }
    }
    return out.slice();
}

!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto words = split_words(arena.allocator(), "one two  three")?;
    println(words.len, words);
}
```

`split_words` never frees anything: the result is a slice into the arena's memory, and the arena releases it all at once. Compare with a function that returned a `List` that the caller had to remember to `deinit`.

## Take slices, return values

For input, take the most general view of the data: `str` instead of a list of characters, `T[]` instead of a `List<T>`. The function then works with arrays, lists, and parts of both, and it cannot reallocate what it was given.

```vibe run
i64 sum(i64[] xs) {
    auto total = 0;
    for (auto x : xs) { total += x; }
    return total;
}

void main() {
    auto arr = [1, 2, 3, 4];
    auto list = List<i64>::init(c_allocator());
    defer list.deinit();
    for (auto x : arr) { list.push(x * 10) catch return; }
    println(sum(arr[..]), sum(arr[1..3]), sum(list.slice()));
}
```

For output, return small values and structs by value. Use an out-parameter only for something big that already exists (a buffer to fill).

## Errors: name them and keep them

Return a named error from the place that understands the problem. Pass errors up with `?` where you cannot do better, and convert them with `catch` only at the place that knows what to do.

```vibe run exit
!i64 read_port(str s) {
    const auto n = parse_int(s) catch { return error.BadPort; };
    if (n < 1 || n > 65535) { return error.PortOutOfRange; }
    return n;
}

!void main() {
    println(read_port("8080")?);
    println(read_port("99999") catch |e| { println("config problem: {e}"); 0; });
    println(read_port("http")?);
}
```

`main` returns `!void`, so an unhandled error becomes the exit message of the program, as the last line shows. Do not use `catch 0` to silence an error unless a zero is really the right answer.

Use `?T` for "there may be nothing" and `!T` for "it may fail". A lookup that finds nothing is not an error:

```vibe run
?str find_name(str[] names, str prefix) {
    for (auto n : names) {
        if (n.len >= prefix.len && n[0..prefix.len] == prefix) { return n; }
    }
    return null;
}

void main() {
    const str[3] names = ["ada", "alan", "grace"];
    println(find_name(names[..], "al") orelse "nobody");
    println(find_name(names[..], "zz") orelse "nobody");
}
```

## Model the data with unions and enums

Make impossible states impossible. A request that is either waiting, running with a progress, or done with a result is a union, not three booleans:

```vibe run
union Job {
    Waiting;
    f64 Running;
    i64 Done;
    str Failed;
}

str progress_text(f64 p) {
    if (p > 0.5) { return "more than half"; }
    return "just started";
}

str result_text(i64 n) {
    if (n > 0) { return "done, has a result"; }
    return "done, empty";
}

str describe(Job j) {
    return match j {
        .Waiting => "waiting",
        .Running(p) => progress_text(p),
        .Done(n) => result_text(n),
        .Failed(why) => why,
    }
}

void main() {
    println(describe(.Waiting));
    println(describe(.Running(0.8)));
    println(describe(.Done(0)));
    println(describe(.Failed("disk full")));
}
```

When you add a variant, every `match` without a `_` arm stops compiling until you handle it. That is the compiler working as a checklist. Avoid `_ =>` arms in a `match` over your own types: they hide exactly this help.

## Let the zero value be useful

A struct literal sets what you name and zeroes the rest, and variables start as zero. Design a type so that the all-zero value is a valid, empty one, and you need no constructor and no flag for "initialized":

```vibe run
struct Stats {
    i64 count;
    i64 total;
    i64 max;

    void add(i64 x) {
        this->count += 1;
        this->total += x;
        if (x > this->max) { this->max = x; }
    }

    f64 mean() {
        if (this->count == 0) { return 0.0; }
        return this->total as f64 / this->count as f64;
    }
}

void main() {
    auto s = Stats{};
    for (auto x : [4, 8, 15, 16, 23, 42]) { s.add(x); }
    println(s.count, s.max, s.mean());
}
```

Types with an allocator are the exception: they need `init`. A zero `List` has no allocator, and `push` on it returns `error.NoAllocator` instead of crashing.

## Interfaces at the edges

Put an interface where your program meets the world: files, the network, the clock, a logger. The logic takes the interface, the program passes the real thing, and a test passes a fake one. No framework is needed.

```vibe test
interface Clock {
    i64 now();
}

struct FakeClock {
    i64 t;
    i64 now() { return this->t; }
}

bool expired(Clock c, i64 deadline) {
    return c.now() >= deadline;
}

test "a deadline in the future is not expired" {
    auto fake = FakeClock{ .t = 100 };
    assert(!expired(&fake, 200));
}

test "a deadline in the past is expired" {
    auto fake = FakeClock{ .t = 300 };
    assert(expired(&fake, 200));
}
```

## Do and do not

| Do | Do not |
|---|---|
| `defer a.free(x)` on the line after the allocation | free at the end of the function by hand |
| take `str` and `T[]` | take `List<T>*` when you only read |
| `?` to pass errors up | `catch 0` to make a warning disappear |
| `match` without `_` on your own unions | a catch-all arm that hides new variants |
| get a pointer into a list late and drop it early | keep `list.at(i)` across a `push` (the compiler refuses) |
| one arena per unit of work | a global allocator that nothing owns |
| `+%` for hashes | `+` where you expect a wrap (it panics on purpose) |
| `comptime assert(sizeof(T) == N)` for layouts | a comment that says "must be 16 bytes" |
| `defer t.join()` or `errdefer t.join()` right after each `spawn` | a join only at the very end, so that a `?` can leave the thread running (the compiler refuses) |
| collect the changes, apply them after the loop | `list.push(...)` inside `for (auto x : list)` (the compiler refuses) |

## What next

- Practice these on small problems: [the course](learn.md).
- The full list of checks: [the safety model](safety.md).
- When a message is unclear: [debugging](debugging.md).
