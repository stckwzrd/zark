---
title: "Learn Zark: a path from zero to a program"
order: 1.5
section: Start
description: A step-by-step course in twelve lessons with exercises and solutions: how to think in Zark, write code that the compiler accepts the first time, and finish with a real tool
---

This page is a course. Every lesson is short, has a program you can run, one idea to notice and an exercise with a solution. Do the lessons in order and type the code yourself instead of copying it: the compiler's messages are part of the teaching.

You need the compiler built as described in [installation](getting-started.md). Put each program in a file, for example `lesson.zk`, and run `zark run lesson.zk`.

How the course is organized:

| Lessons | Topic | What you can do afterwards |
|---|---|---|
| 1–3 | values, types, control flow, functions | write small calculations and scripts |
| 4–5 | structs, unions, errors | model data and handle failure |
| 6–8 | memory, slices, ownership | use the heap without fear |
| 9–10 | interfaces, closures, generics | share code between types |
| 11–12 | tests, comptime, a whole tool | ship a finished program |

> **How to learn from this page:** before you run an example, say out loud what you expect it to print. When the output surprises you, stop and find out why: that surprise is the lesson.

## Lesson 1. Values and printing

Everything starts in `main`. `println` prints its arguments separated by spaces; inside a string, an expression in curly braces is computed and substituted.

```zark run
void main() {
    const auto name = "Zark";
    auto year = 2026;
    year += 1;
    println("Hello, {name}! Next year is {year}.");
    println(name.len, year, 7 / 2, 7 % 2, 7.0 / 2.0);
}
```

Notice three things. `const` forbids changing a variable and the plain form allows it. `auto` lets the compiler infer the type. `7 / 2` is `3`, because integer division drops the fraction.

**Exercise.** Print the average of `3`, `4` and `8` as a number with two digits after the decimal point. Hint: convert before you divide, and use `{x:.2}` in the string.

```zark run
void main() {
    const auto sum = 3 + 4 + 8;
    const auto avg = sum as f64 / 3 as f64;
    println("average = {avg:.2}");
}
```

## Lesson 2. Types and why conversions are visible

Integers have a size and a sign: `i8`, `i16`, `i32`, `i64` and `u8` … `u64`. Floats are `f32` and `f64`. A value moves to a bigger type of the same kind on its own, and everything else needs `as`.

```zark run
void main() {
    const i32 small = 70000;
    const i64 wide = small;
    const auto back = wide as i16;
    println(wide, back);
    println(3.99 as i64, -1 as u8, 300.5 as u8);
}
```

`wide as i16` keeps only what fits (`4464`). A float outside the range of the integer type does not do anything dangerous: it becomes the nearest limit (`300.5 as u8` is `255`).

Arithmetic that does not fit is not allowed to go unnoticed. In a normal build it stops the program with a message that has the file and the line:

```zark run exit
void main() {
    u8 level = 250;
    for (auto i : 0..10) {
        level += 1;
        println(level);
    }
}
```

When wrapping is exactly what you want (a hash, a counter that goes round), say it with `+%`, `-%` and `*%`.

```zark run
void main() {
    u8 level = 250;
    for (auto i : 0..10) { level = level +% 1; }
    println(level);
}
```

**Exercise.** What does `200 as u8 + 100 as u8` do? Write it down, then run it.

```zark run exit
void main() {
    const u8 a = 200;
    const u8 b = 100;
    println(a + b);
}
```

The answer is a panic, not `44`. To get `44`, write `a +% b`.

## Lesson 3. Control flow and functions

`if`, `while` and `for` work as you expect. A range `a..b` includes `a` and excludes `b`. A function has its return type in front of the name.

```zark run
bool is_prime(i64 n) {
    if (n < 2) { return false; }
    for (auto d : 2..n) {
        if (d * d > n) { break; }
        if (n % d == 0) { return false; }
    }
    return true;
}

void main() {
    for (auto n : 1..30) {
        if (is_prime(n)) { print("{n} "); }
    }
    println("");
}
```

Notice that the loop variable `d` is created by the loop and cannot be changed inside it, and that `break` leaves only the nearest loop.

**Exercise.** Write `gcd(a, b)` with Euclid's algorithm, then print `gcd(48, 18)`.

```zark run
i64 gcd(i64 a, i64 b) {
    while (b != 0) {
        const auto t = a % b;
        a = b;
        b = t;
    }
    return a;
}

void main() {
    println(gcd(48, 18));
}
```

Parameters are copies, so changing `a` and `b` inside the function does not touch the caller's variables.

## Lesson 4. Structs, methods and unions

A struct groups fields. Methods are written inside it and use `this`. A literal names the fields it sets, and everything else is zero.

```zark run
struct Account {
    str owner;
    i64 cents;

    static Account open(str owner) {
        return Account{ .owner = owner };
    }

    void deposit(i64 amount) {
        this->cents += amount;
    }

    str describe() {
        return this->owner;
    }
}

void main() {
    auto acc = Account::open("Ada");
    acc.deposit(1500);
    acc.deposit(250);
    println(acc.describe(), acc.cents);
}
```

When a value can be one of several different shapes, use a `union`: it carries a tag, and `match` forces you to handle every shape.

```zark run
union Cmd {
    i64 Push;
    Pop;
    Add;
}

void main() {
    const Cmd[4] program = [.Push(2), .Push(40), .Add, .Pop];
    i64[16] stack;
    auto top = 0;
    for (auto c : program) {
        match c {
            .Push(v) => { stack[top] = v; top += 1; }
            .Add => { stack[top - 2] = stack[top - 2] + stack[top - 1]; top -= 1; }
            .Pop => { top -= 1; println("popped {stack[top]}"); }
        }
    }
}
```

A `match` statement may skip variants: nothing happens for them. A `match` that produces a value has to cover every variant, and the compiler names the one that is missing. That is the point of choosing this form when a forgotten case would be a bug: when you add a variant to the union, every such place stops compiling until you handle it.

```zark error
union Shape {
    f64 Circle;
    i64 Square;
    Empty;
}

f64 area(Shape s) {
    return match s {
        .Circle(r) => 3.14 * r * r,
        .Square(w) => w as f64,
    }
}

void main() { println(area(.Empty)); }
```

**Exercise.** Add a `Dup` command that duplicates the top of the stack, and use it in the program.

```zark run
union Cmd {
    i64 Push;
    Dup;
    Add;
    Print;
}

void main() {
    const Cmd[5] program = [.Push(21), .Dup, .Add, .Print, .Print];
    i64[16] stack;
    auto top = 0;
    for (auto c : program) {
        match c {
            .Push(v) => { stack[top] = v; top += 1; }
            .Dup => { stack[top] = stack[top - 1]; top += 1; }
            .Add => { stack[top - 2] = stack[top - 2] + stack[top - 1]; top -= 1; }
            .Print => { println(stack[top - 1]); }
        }
    }
}
```

## Lesson 5. Errors are values

A function that can fail returns `!T`. The caller has to do something about it: pass it up with `?`, give a default with `catch`, or look at it with `catch |e|`. Ignoring the result does not compile.

```zark run exit
!i64 parse_age(str s) {
    const auto n = parse_int(s)?;
    if (n < 0 || n > 150) { return error.OutOfRange; }
    return n;
}

!void main() {
    println(parse_age("42")?);
    println(parse_age("200") catch -1);
    println(parse_age("old") catch |e| { println("could not parse: {e}"); -2; });
    println(parse_age("-5")?);
    println("not reached");
}
```

The last call returns an error from `main`, and the program ends with `error: OutOfRange` and a failure code. Nothing was thrown and nothing unwound the stack: the error is just a return value that you passed along.

An error is not a panic. Errors are for things that can happen in a correct program: a missing file, bad input, no memory. A panic is for a bug: an index out of range, a division by zero, an overflow. A panic cannot be caught, and that is deliberate.

**Exercise.** Write `!i64 safe_div(i64 a, i64 b)` that returns `error.DivideByZero` instead of panicking.

```zark run
!i64 safe_div(i64 a, i64 b) {
    if (b == 0) { return error.DivideByZero; }
    return a / b;
}

void main() {
    println(safe_div(10, 2) catch 0);
    println(safe_div(1, 0) catch -1);
}
```

## Lesson 6. Memory is yours, and the compiler helps

Nothing in Zark allocates behind your back. To get heap memory you hold an allocator and pass it where it is needed. `defer` puts the cleanup next to the allocation, so it cannot be forgotten, and runs it however the function ends.

```zark run
!void main() {
    const auto a = c_allocator();
    auto numbers = List<i64>::init(a);
    defer numbers.deinit();

    for (auto i : 1..6) { numbers.push(i * i)?; }
    println(numbers.slice(), numbers.len);

    const auto one = a.create<i64>()?;
    defer a.destroy(one);
    *one = 7;
    println(*one);
}
```

Now the part that makes Zark comfortable. The mistakes that make C programs crash are refused while compiling. Free something and then use it, and the compiler points at the exact line:

```zark error
void main() {
    const auto a = c_allocator();
    auto p = a.create<i64>() catch return;
    *p = 7;
    a.destroy(p);
    println(*p);
}
```

Free something twice, even through a `defer`, and it is refused as well. Keep a pointer into a list and then add to the list (the buffer may move), and it is refused:

```zark error
void main() {
    auto l = List<i64>::init(c_allocator());
    defer l.deinit();
    l.push(1) catch return;
    auto first = l.at(0);
    l.push(2) catch return;
    println(*first);
}
```

The fix is in the message: take the pointer again after the change.

```zark run
void main() {
    auto l = List<i64>::init(c_allocator());
    defer l.deinit();
    l.push(1) catch return;
    l.push(2) catch return;
    auto first = l.at(0);
    *first = 10;
    println(l.get(0), l.get(1));
}
```

When you create many small objects with one lifetime, do not free them one by one. Use an arena: allocate freely and release everything with one `deinit`.

```zark run
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    auto words = List<str>::init(a);
    for (auto w : ["alpha", "beta", "gamma"]) { words.push(a.dup(w)?)?; }
    println(words.slice());
}
```

**Exercise.** The function below leaks on the error path. Fix it so that nothing is lost if the second allocation fails.

```zark run
!i64 sum_two(Allocator a) {
    const auto x = a.create<i64>()?;
    defer a.destroy(x);
    const auto y = a.create<i64>()?;
    defer a.destroy(y);
    *x = 20;
    *y = 22;
    return *x + *y;
}

void main() {
    println(sum_two(c_allocator()) catch 0);
}
```

Putting `defer` right after each allocation is the whole technique. If you need the memory to live on after the function returns on success, use `errdefer`, which runs only when the function returns an error.

## Lesson 7. Slices and strings

A slice `T[]` is a pointer and a length: a view into memory that somebody else owns. `str` is a slice of bytes. Slicing never copies. Every access is checked: an index out of range is a panic with the position, not a silent read of someone else's memory.

```zark run
void main() {
    const auto s = "hello, world";
    const auto word = s[7..];
    println(word, word.len, s[0..5]);
    const auto xs = [10, 20, 30, 40];
    println(xs[1..3], xs[..2]);
}
```

```zark run exit
void main() {
    const auto xs = [1, 2, 3];
    auto i = 3;
    println(xs[i]);
}
```

Because a slice only borrows, the compiler watches where it came from. A slice of a local array cannot be returned from the function, since the array dies with the function:

```zark error
u8[] first_four() {
    u8[16] buf;
    return buf[0..4];
}

void main() { println(first_four().len); }
```

The way out is the same as in every language with manual memory: the caller provides the storage, or the function allocates it with an allocator that the caller passes in.

**Exercise.** Write `count_words(str s)` that returns the number of space-separated words. Use only indexing and a loop.

```zark run
i64 count_words(str s) {
    auto n = 0;
    auto in_word = false;
    for (auto c : s) {
        if (c == ' ') {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            n += 1;
        }
    }
    return n;
}

void main() {
    println(count_words("to be or not to be"), count_words("  "), count_words(""));
}
```

## Lesson 8. Reading the compiler

Programs in this language are written together with the compiler, so learn to read it. Every message has the file, the line, the source line with a caret under the place, and usually the fix. Three habits make this fast.

1. Read the **first** error only. Later ones are often consequences.
2. Read the **caret**, not only the text: it shows which expression is meant.
3. When a message says "consumed" or "points into", it is describing *when* something stopped being valid. Look at the line it names.

A short catalogue of messages you will meet in the first week:

```zark error
void main() {
    const i64 big = 5;
    const i32 small = big;
}
```

Narrowing needs `as`. The compiler never guesses that you accept losing bits.

```zark error
void main() {
    const auto x = 10;
    x = 11;
}
```

`const` means constant. Remove it if the variable has to change.

```zark error
!i64 half(i64 n) {
    if (n % 2 != 0) { return error.Odd; }
    return n / 2;
}

void main() {
    half(4);
}
```

An error union cannot be dropped silently. Use `?`, `catch` or `_ =` to say what you want.

```zark error
void main() {
    auto n = 5;
    println(comptime n + 1);
}
```

`comptime` runs while compiling, so it cannot see variables that exist only when the program runs (lesson 11).

## Lesson 9. Interfaces

An interface is a list of methods. Any struct with those methods can be used through it, with no declaration of the relationship. A call goes through a pointer, so the object must outlive the interface value.

```zark run
interface Sink {
    void write(str s);
}

struct Counter {
    i64 bytes;
    void write(str s) { this->bytes += s.len; }
}

struct Echo {
    void write(str s) { print(s); }
}

void log_all(Sink sink, str[] lines) {
    for (auto l : lines) {
        sink.write(l);
        sink.write("\n");
    }
}

void main() {
    auto c = Counter{};
    auto e = Echo{};
    const str[2] lines = ["first", "second"];
    log_all(&e, lines[..]);
    log_all(&c, lines[..]);
    println("counted {c.bytes} bytes");
}
```

Notice that `log_all` knows nothing about `Counter` or `Echo`. This is how you make code testable: pass a `Counter` in a test and an `Echo` in the program.

**Exercise.** Add a `Prefixed` sink that writes a prefix before every line it receives. Keep it independent of `Echo`.

```zark run
interface Sink {
    void write(str s);
}

struct Echo {
    void write(str s) { print(s); }
}

struct Prefixed {
    Sink inner;
    str prefix;
    void write(str s) {
        this->inner.write(this->prefix);
        this->inner.write(s);
    }
}

void main() {
    auto e = Echo{};
    auto p = Prefixed{ .inner = &e, .prefix = "> " };
    p.write("hello\n");
}
```

## Lesson 10. Closures and generics

A closure lists the variables it uses, and by what means: `[&k]` is a reference. The context lives on the stack and nothing is allocated, so a closure must not outlive the variables it points at.

```zark run
void each(i64[] xs, fn[](i64) -> void body) {
    for (auto x : xs) { body(x); }
}

void main() {
    const auto xs = [3, 1, 4, 1, 5];
    auto total = 0;
    auto biggest = 0;
    each(xs[..], [&total, &biggest](i64 x) -> void {
        total += x;
        if (x > biggest) { biggest = x; }
    });
    println(total, biggest);
}
```

A function or struct can be generic with `template<T>`. A constraint such as `T: Ord` states what the type must support. The body is checked against it at the declaration, and a call with a type that does not satisfy it is reported at the call.

```zark run
template<T: Ord> T largest(T[] xs) {
    auto best = xs[0];
    for (auto x : xs) { if (x > best) { best = x; } }
    return best;
}

void main() {
    println(largest([3, 9, 2][..]), largest([1.5, 0.5][..]));
}
```

**Exercise.** Write `template<T> i64 count_if(T[] xs, fn[](T) -> bool pred)` and use it to count the even numbers in a list.

```zark run
template<T> i64 count_if(T[] xs, fn[](T) -> bool pred) {
    auto n = 0;
    for (auto x : xs) { if (pred(x)) { n += 1; } }
    return n;
}

void main() {
    const auto xs = [1, 2, 3, 4, 5, 6];
    println(count_if(xs[..], [](i64 x) -> bool { return x % 2 == 0; }));
}
```

## Lesson 11. Tests and `comptime`

Tests are part of the language. A `test` block sits next to the code it checks and runs with `zark test`. Write the test first when you can: it shows you the interface you want.

```zark test
i64 clamp(i64 x, i64 lo, i64 hi) {
    if (x < lo) { return lo; }
    if (x > hi) { return hi; }
    return x;
}

test "inside the range nothing changes" {
    assert(clamp(5, 0, 10) == 5);
}

test "values are pulled to the edges" {
    assert(clamp(-3, 0, 10) == 0);
    assert(clamp(99, 0, 10) == 10);
}
```

`comptime` runs ordinary code while compiling. It is the right tool for tables you would otherwise type by hand and for checks that must never be forgotten:

```zark run
struct Header { u8 kind; u8 flags; u16 length; }

comptime assert(sizeof(Header) == 4);

u8[16] make_squares() {
    u8[16] t;
    for (auto i : 0..16) { t[i] = (i * i % 256) as u8; }
    return t;
}

const auto SQUARES = comptime make_squares();

void main() {
    println(SQUARES[7], SQUARES[15]);
}
```

If somebody adds a field to `Header`, the build fails at the `comptime assert` instead of the file format silently changing. See [compile-time evaluation](comptime.md).

**Exercise.** Write a test that checks `clamp` returns `lo` when `lo` equals `hi`.

```zark test
i64 clamp(i64 x, i64 lo, i64 hi) {
    if (x < lo) { return lo; }
    if (x > hi) { return hi; }
    return x;
}

test "a single allowed value" {
    assert(clamp(-5, 3, 3) == 3);
    assert(clamp(50, 3, 3) == 3);
}
```

## Lesson 12. A whole tool

Now put the pieces together: a program that counts the words in a text, handles every failure, uses an arena for all its memory and keeps the logic in a separate function that takes a `str`, so a test needs no file.

```zark run
!void count(str text, Map<i64>* counts, List<str>* order) {
    auto start = 0;
    for (auto i : 0..text.len + 1) {
        const auto end = i == text.len || text[i] == ' ' || text[i] == '\n';
        if (!end) { continue; }
        if (i > start) {
            const auto w = text[start..i];
            if (!counts.has(w)) { order.push(w)?; }
            counts.put(w, (counts.get(w) catch 0) + 1)?;
        }
        start = i + 1;
    }
}

!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    auto counts = Map<i64>::init(a);
    auto order = List<str>::init(a);
    count("to be or not to be\nthat is the question", &counts, &order)?;

    for (auto w : order) {
        println("{w}: {counts.get(w)?}");
    }
    if (order.len == 0) { return error.NoWords; }
}
```

Read the program as a checklist of the habits of the course:

- all memory comes from one arena, freed by one `defer`;
- every call that can fail is followed by `?` or `catch`;
- the pure function `count` is easy to test, and `main` only wires things together;
- nothing here can read outside a string, because every index is checked.

**Finish line.** Extend the tool in three steps. Each one teaches a different part of the language:

1. Read the text from a file given on the command line (`args`, `read_file`; see [recipes](cookbook.md)).
2. Sort the result by count (the [standard library](stdlib.md) has `sort`).
3. Write tests for `count` with empty text, repeated spaces and one very long word.

## The ten habits

1. Put `defer` or `errdefer` on the line after the allocation.
2. Pass the allocator in as a parameter. Do not hide a global one.
3. Prefer slices to pointers and indexes to pointer arithmetic.
4. Return errors, panic only for bugs.
5. Keep pure logic in functions that take plain values, and test them.
6. Make illegal states unrepresentable with `union` and `enum`, and let `match` check you.
7. Use `+%` only where wrapping is the meaning.
8. Take a pointer into a container as late as possible and let it go as soon as you are done.
9. Do not fight the compiler: if a rule seems to block you, the message names the line where the trouble starts.
10. Turn on `-O` for speed, `-g` for debugging, and keep `--release` for programs that you have already tested in the safe mode.

## Where to go next

- The reasoning behind the checks, and what they do not cover: [the safety model](safety.md).
- How to write code that other people enjoy reading: [idioms](idioms.md).
- When something does not work: [debugging](debugging.md).
- To see big programs: the [showcase](showcase.md) and the [cookbook](cookbook.md).
