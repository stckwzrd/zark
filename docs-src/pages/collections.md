---
title: "Collections: List, Map, Option"
order: 21
section: Memory and data
description: The dynamic array List<T>, the hash table Map<V>, Option<T>, sorting and the helper functions of the Zark standard library
---

Containers in Zark are ordinary generic structs written in Zark itself (the source is `std/std.zk`, which is included automatically). There is no magic in them, and they obey the main rule: **memory is taken only through an explicit allocator**.

Which container to choose:

| You need | Take |
|---|---|
| a set of elements of known size | an array `T[N]` on the stack |
| a set of elements whose size grows | `List<T>` |
| looking up a value by a string key | `Map<V>` |
| "a value or nothing" | `?T` / `Option<T>` |

## `List<T>`: a dynamic array

```zark run
!void main() {
    auto xs = List<i64>::init(c_allocator());
    defer xs.deinit();

    xs.push(5)?;
    xs.push(1)?;
    xs.push(3)?;
    println(xs.slice(), xs.len);
}
```

Three rules:

1. `List<T>::init(a)` remembers the allocator. Before `init` a list has no allocator, and `push` on a "zero" list will not work.
2. Any **growing** action returns `!void`: memory can run out. Write `?` or `catch`.
3. At the end call `deinit()`. For an arena it is not needed (see [memory](memory.md#arena-allocate-a-lot-free-at-once)).

### The structure of a list

```zark
struct List<T> {
    T[] items;   // the allocated buffer, items.len is the capacity
    i64 len;     // how many elements are actually there
    Allocator a;
}
```

So `xs.len` is the number of elements, and `xs.items.len` is the capacity. The buffer grows by doubling: 8, 16, 32 and so on.

### Methods

| Method | What it does |
|---|---|
| `init(a)` | creates an empty list |
| `deinit()` | frees the buffer |
| `!void push(v)` | appends to the end |
| `!void append(slice)` | appends several |
| `!T pop()` | removes and returns the last; `error.Empty` on an empty list |
| `!T last()` | the last one without removing it; `error.Empty` on an empty list |
| `T get(i)` | an element (with a bounds check) |
| `set(i, v)` | writes an element |
| `T[] slice()` | the current elements as a slice |
| `bool is_empty()` | whether it is empty |
| `clear()` | resets the length to zero, the memory stays |
| `bool contains(v)` | whether there is such an element (needs `==`) |
| `reverse()` | reverses in place |
| `sort()` | sorts in place (needs `<`, `>`) |
| `!void reserve(n)` | allocates capacity in advance |

```zark run
!void main() {
    auto xs = List<i64>::init(c_allocator());
    defer xs.deinit();

    xs.push(5)?;
    xs.push(1)?;
    xs.push(3)?;
    xs.append([9, 7])?;
    println(xs.slice(), xs.len, xs.is_empty());
    println(xs.contains(3), xs.contains(4));

    println(xs.get(1), xs.last()?, xs.pop()?);
    xs.set(0, 50);
    xs.sort();
    println(xs.slice());
    xs.reverse();
    println(xs.slice());

    xs.reserve(100)?;
    println(xs.len, xs.items.len);
    xs.clear();
    println(xs.len, xs.pop() catch -1);
}
```

### Iterating

`for` can iterate over anything that has `slice()`, so a list goes straight into a loop:

```zark run
!void main() {
    auto xs = List<i64>::init(c_allocator());
    defer xs.deinit();
    for (auto i : 1..5) { xs.push(i * 10)?; }

    for (auto x : xs) { println(x); }
    for (auto [i, x] : xs) { println("{i}: {x}"); }

    auto total = 0;
    for (auto x : xs.slice()) { total += x; }
    println(total);
}
```

### Changing elements in place

`get` returns a **copy**. To change the elements of structs, take a pointer to the element:

```zark run
struct Player { str name; i64 score; }

!void main() {
    auto ps = List<Player>::init(c_allocator());
    defer ps.deinit();
    ps.push(Player{ .name = "ann", .score = 1 })?;
    ps.push(Player{ .name = "bob", .score = 2 })?;

    auto copy = ps.get(0);
    copy.score = 100;
    println(ps.get(0).score);

    const auto p = &ps.items[0];
    p.score = 99;
    println(ps.get(0).score);

    for (auto i : 0..ps.len) { ps.items[i].score += 1; }
    for (auto p : ps) { println(p.name, p.score); }
}
```

> **Gotcha:** a pointer to an element (`&ps.items[0]`) is invalid after a `push`: the list may have moved its buffer to another place. Do not keep such pointers if you are going to add elements.

### Stack, queue, slices

A stack is `push` + `pop`:

```zark run
!void main() {
    auto st = List<i64>::init(c_allocator());
    defer st.deinit();
    st.push(1)?;
    st.push(2)?;
    st.push(3)?;
    while (!st.is_empty()) {
        println(st.pop()?);
    }
}
```

A slice of a list (`xs.slice()`) can be sliced further too (`xs.slice()[1..3]`), but it "watches" the same data and becomes stale together with the buffer.

### A list in a list

```zark run
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    auto rows = List<List<i64 >>::init(a);
    for (auto r : 0..3) {
        auto row = List<i64>::init(a);
        for (auto c : 0..3) { row.push(r * 3 + c)?; }
        rows.push(row)?;
    }
    for (auto r : rows) { println(r.slice()); }
}
```

Here the arena frees everything at once, so the nested lists do not need `deinit`.

## `Map<V>`: a hash table with string keys

The key is always a `str`, and the value is any type `V`.

```zark run
!void main() {
    auto m = Map<i64>::init(c_allocator());
    defer m.deinit();

    m.put("one", 1)?;
    m.put("two", 2)?;
    m.put("one", 11)?;

    println(m.get("one")?);
    println(m.get("zzz") catch -1);
    println(m.has("two"), m.has("x"), m.len);
}
```

| Method | What it does |
|---|---|
| `init(a)` | an empty table |
| `deinit()` | frees the memory |
| `!void put(key, value)` | adds or replaces |
| `!V get(key)` | the value or `error.NotFound` |
| `bool has(key)` | whether the key exists |
| `len` | the number of keys |

> **Gotcha:** keys are **not copied**: the table stores the slice you gave it. If a key is built from a temporary buffer, copy it with `a.dup(key)`, otherwise it will be corrupted when the buffer is overwritten.

You cannot delete keys (there is no `remove` method). `get` returns a copy of the value: to change a value in place you need to work with `m.entries`.

### Iterating

There is no special iterator, but the table is an array of records `entries`, and the occupied records are marked `used`:

```zark run
!void main() {
    auto m = Map<i64>::init(c_allocator());
    defer m.deinit();
    m.put("a", 1)?;
    m.put("b", 2)?;
    m.put("c", 3)?;

    auto total = 0;
    for (auto e : m.entries) {
        if (e.used) {
            total += e.value;
        }
    }
    println(total, m.len);

    for (auto e : m.entries) {
        if (e.used && e.key == "b") { println("found {e.key} = {e.value}"); }
    }
}
```

The order of traversal is the order of the hash table's slots, not the order of insertion. Do not rely on it.

### A word counter

A typical task: count how many times each word occurs.

```zark run
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    const auto text = "to be or not to be";
    auto counts = Map<i64>::init(a);
    auto start = 0;
    for (auto i : 0..text.len + 1) {
        if (i == text.len || text[i] == ' ') {
            const auto w = text[start..i];
            const auto n = counts.get(w) catch 0;
            counts.put(w, n + 1)?;
            start = i + 1;
        }
    }
    println(counts.get("to")?, counts.get("be")?, counts.get("or")?, counts.len);
}
```

The keys here are slices of `text`, and `text` is a literal that lives for the whole run, so the keys do not need copying.

### Struct values

```zark run
struct Stat { i64 count; i64 sum; }

!void main() {
    auto m = Map<Stat>::init(c_allocator());
    defer m.deinit();
    m.put("a", Stat{ .count = 1, .sum = 10 })?;
    const auto s = m.get("a")?;
    println(s.count, s.sum);
}
```

## `Option<T>` and `?T`

`?T` is the notation for `Option<T>`: a union with the variants `Some: T` and `None`. Described in detail in [errors and optional values](errors-and-optionals.md#optional-values-t).

```zark run
void main() {
    const ?i64 a = .Some(5);
    const ?i64 b = .None;
    println(a.is_some(), b.is_some(), b.unwrap_or(9));
    println(a orelse 0, b orelse 0);
}
```

## Sorting and helper functions

| Function | What it does |
|---|---|
| `sort(slice)` | a fast in-place sort; the elements need `<` and `>` |
| `min(a, b)`, `max(a, b)` | the smaller and the larger |
| `abs(x)` | the absolute value of a number |
| `swap(&a, &b)` | swaps two values |

```zark run
void main() {
    auto xs = [5, 2, 9, 1];
    sort(xs[..]);
    println(xs);
    auto fs = [3.5, 1.5, 2.5];
    sort(fs[..]);
    println(fs);
    println(min(3, 4), max(3.5, 1.0), abs(-5), abs(-2.5));
    auto a = 1;
    auto b = 2;
    swap(&a, &b);
    println(a, b);
}
```

`sort` cannot sort strings or structs (they have no `<`). For them, write your own loop with your own comparison function.

### Sorting by a key

```zark run
struct P { str name; i64 age; }

void sort_by_age(P[] ps) {
    for (auto i : 1..ps.len) {
        auto j = i;
        while (j > 0 && ps[j - 1].age > ps[j].age) {
            swap(&ps[j - 1], &ps[j]);
            j -= 1;
        }
    }
}

void main() {
    auto ps = [P{ .name = "a", .age = 30 }, P{ .name = "b", .age = 20 }, P{ .name = "c", .age = 25 }];
    sort_by_age(ps[..]);
    for (auto p : ps) { println(p.name, p.age); }
}
```

## Arrays and slices

If the size is known in advance, you do not need a list. An array on the stack is faster, allocates nothing and needs no `deinit`:

```zark run
void main() {
    i64[3][3] grid;
    for (auto r : 0..3) {
        for (auto c : 0..3) {
            grid[r][c] = r * 3 + c;
        }
    }
    println(grid);
    println(grid[1][2], grid.len, grid[0].len);
}
```

Functions take a **slice**, so the same function works with an array and with a list (`xs.slice()`):

```zark run
i64 total(i64[] xs) {
    auto t = 0;
    for (auto x : xs) { t += x; }
    return t;
}

!void main() {
    const auto arr = [1, 2, 3];
    auto list = List<i64>::init(c_allocator());
    defer list.deinit();
    list.append([10, 20])?;
    println(total(arr[..]), total(list.slice()));
}
```

## What next

- The allocators themselves: [memory and allocators](memory.md).
- A reference of all functions: [standard library](stdlib.md).
