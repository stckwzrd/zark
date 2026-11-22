---
title: Structs, unions and enums
order: 16
section: Language
description: struct and methods, enum, tagged union, generic structs, memory layout and taking them apart with match
---

There are three ways to describe your own data type:

| | What it stores | Example |
|---|---|---|
| `struct` | **all** the fields at once | a point with `x` and `y` |
| `enum` | one of a set of **names** | a direction: north, south |
| `union` | one of several **variants**, each with its own data | a shape: a circle with a radius or a rectangle |

## `struct`

```zark run
struct Point {
    i64 x;
    i64 y;
}

void main() {
    const auto p = Point{ .x = 3, .y = 4 };
    println(p.x, p.y);
    println(p);
}
```

A field is declared like a variable: type, name, `;`. A struct is printed as `Name{ field: value }`.

All structs are laid out in memory as in C: the fields go in order, with padding added between them. The size is available through `sizeof`:

```zark run
struct Small { u8 a; u8 b; u8 c; }
struct Padded { u8 a; i64 b; u8 c; }

void main() {
    println(sizeof(Small), sizeof(Padded), alignof(Padded));
}
```

The order of fields affects the size: big fields first, small ones after, and the struct will be more compact.

### The struct literal

A literal is written as `Name{ .field = value, ... }`. It is recognized only if the type name starts with a **capital** letter.

Fields that are missing from the literal are filled with zeros. `Name{}` has all fields zero:

```zark run
struct Config {
    i64 width;
    i64 height;
    str title;
    bool visible;
}

void main() {
    const auto a = Config{ .width = 800, .height = 600, .title = "window", .visible = true };
    const auto b = Config{ .width = 100 };
    const auto c = Config{};
    println(a);
    println(b);
    println(c.width, c.title.len);
}
```

A typo in a field name is a compile error:

```zark error
struct P { i64 x; i64 y; }

void main() {
    const auto p = P{ .x = 1, .y = 2, .w = 3 };
}
```

Defaults can be given in the field declaration (see [defaults and constructors](#defaults-and-constructors)); a field without one is always zero.

### Structs are copied

Assignment and passing to a function copy all the fields:

```zark run
struct P { i64 x; i64 y; }

void main() {
    auto a = P{ .x = 1, .y = 2 };
    auto b = a;
    b.x = 99;
    println(a.x, b.x);
}
```

To work with one object, pass a pointer `P*` (fields are read through it with a plain dot).

### Nested structs and arrays

```zark run
struct Point { i64 x; i64 y; }
struct Line { Point a; Point b; }
struct Poly { Point[3] pts; i64 n; }

void main() {
    const auto l = Line{ .a = Point{ .x = 0, .y = 0 }, .b = Point{ .x = 3, .y = 4 } };
    println(l.b.x, l);
    auto poly = Poly{};
    poly.pts[1].x = 5;
    poly.n = 2;
    println(poly);
}
```

### Referring to itself

A struct cannot contain **itself** by value, but it can contain a pointer to itself:

```zark run
struct Node {
    i64 val;
    Node* next;
}

void main() {
    auto a = Node{ .val = 1, .next = null };
    auto b = Node{ .val = 2, .next = &a };
    println(b.next.val, a.next == null);
}
```

### Comparison

`==` is not defined for structs. Compare the fields:

```zark error
struct A { i64 x; }

void main() {
    const auto a = A{ .x = 1 };
    println(a == a);
}
```

## Methods

Functions tied to a type are written right inside the `struct`. Inside a method the fields are available by their bare names, and also through `this`.

```zark run
struct Counter {
    i64 n;
    static Self new() {
        return Self{ .n = 0 };
    }

    void inc() {
        this->n += 1;
    }

    i64 get() {
        return this->n;
    }
}

void main() {
    auto c = Counter::new();
    c.inc();
    c.inc();
    println(c.get());
    const auto p = &c;
    p.inc();
    println(p.get(), c.n);
}
```

- `Self` inside a `struct` is the type itself.
- A method with `static` is static, without `this`: it is called as `Type::name(...)`.
- Other methods receive `this`, a **pointer** to the object, and can change the fields. They can be called on a value and on a pointer.
- There is no by-copy form: if a method must not change the object, make a copy yourself: `auto c = *this;`.

```zark run
struct V {
    i64 n;
    void by_ptr() { this->n += 1; }
    i64 by_copy() {
        auto c = *this;
        c.n += 100;
        return c.n;
    }
}

void main() {
    auto v = V{ .n = 1 };
    v.by_ptr();
    println(v.by_copy(), v.n);
}
```

> **Gotcha:** a method changes the object even when it is declared with `const`: the compiler hands the method a pointer and does not check mutability. A method with `const` after the parameter list cannot assign fields or call non-const methods through `this`. From outside, the compiler checks the object only for direct assignment `p.x = ...`: calling a method on a `const` variable is allowed. If an object must not change, do not call mutating methods on it.

## `enum`

An enumeration is a set of names. The value is stored as an integer (the ordinal number of the variant, from zero).

```zark run
enum Color { Red, Green, Blue }

void main() {
    const Color c = .Green;
    println(c, Color::Blue, c == .Green, c != .Red);
    println(Color::Blue as i64, 1 as Color);
}
```

The literal `.Name` works when the type is known from the context: for `const Color c`, for a function parameter, for a `return`, for the second operand of a comparison. Without a context, write `Color::Green`.

You cannot set the number of a variant (`A = 5`): it is always 0, 1, 2 and so on.

You can walk over all the values through a conversion from an integer:

```zark run
enum Day { Mon, Tue, Wed }

void main() {
    for (auto i : 0..3) {
        const auto d = i as Day;
        println(i, d);
    }
}
```

> **Gotcha:** the conversion `number as Enum` does not check the range: `7 as Day` gives a value "not from the list", and `match` will not find a match for it.

### `match` on an enum

```zark run
enum Dir { North, East, South, West }

Dir turn(Dir d) {
    return match d {
        .North => .East,
        .East => .South,
        .South => .West,
        .West => .North,
    }
}

void main() {
    Dir d = .North;
    for (auto i : 0..5) {
        println(d);
        d = turn(d);
    }
}
```

As a `match` expression it must cover all the variants. More: [control flow](control-flow.md#match).

### Methods on an enum

```zark run
enum Level {
    Low, High;

    str label() {
        return match *this {
            .Low => "low",
            .High => "high",
        };
    }

    Level flip() {
        return match *this {
            .Low => .High,
            .High => .Low,
        };
    }
}

void main() {
    const Level l = .Low;
    println(l.label(), l.flip().label());
}
```

Inside a method `this` is a pointer, so dereference it: `match *this { ... }`.

## `union`: a sum type (tagged union)

A union stores **one of its variants**, and together with it a tag that says which one. A variant can have a payload (data) of any type, or none.

```zark run
union Shape {
    f64 Circle;
    i64 Rect;
    Empty;
}

void main() {
    const Shape a = .Circle(2.5);
    const auto b = Shape::Rect(4);
    const Shape c = .Empty;
    println(a, b, c);
}
```

Layout: `{ i32 tag, payload }`; the size is determined by the largest variant.

```zark run
union V { i64 I; f64 F; str S; N; }

void main() {
    println(sizeof(V));
}
```

### Taking it apart with `match`

The pattern `.Variant(name)` binds the payload. The bound value is a copy, read-only.

```zark run
union Shape {
    f64 Circle;
    i64 Rect;
    Empty;
}

f64 area(Shape s) {
    return match s {
        .Circle(r) => 3.14 * r * r,
        .Rect(w) => w as f64 * w as f64,
        .Empty => 0.0,
    }
}

void main() {
    println(area(.Circle(1.0)), area(.Rect(3)), area(.Empty));
}
```

Testing a single variant without taking it apart is `is`:

```zark run
union Msg { str Text; Quit; }

void main() {
    const Msg m = .Quit;
    println(m is .Quit, m is .Text);
}
```

### A union as state and as a result

A union is convenient where a value comes in different kinds. For example, parsing a token:

```zark run
union Token {
    i64 Num;
    Plus;
    Minus;
    End;
}

void show(Token t) {
    match t {
        .Num(n) => println("number {n}");
        .Plus => println("+");
        .Minus => println("-");
        .End => println("end");
    }
}

void main() {
    const auto toks = [Token::Num(1), Token::Plus, Token::Num(2), Token::End];
    for (auto t : toks) { show(t); }
}
```

### Methods on a union

```zark run
union Shape {
    f64 Circle;
    i64 Rect;
    static Self circle(f64 r) {
        return Self::Circle(r);
    }

    f64 area() {
        return match *this {
            .Circle(r) => r * r * 3.0,
            .Rect(w) => w as f64,
        }
    }
}

void main() {
    const auto s = Shape::circle(2.0);
    println(s.area());
}
```

## Defaults and constructors

A field can have a default value. It is applied when a struct is created with a literal (`T{}`, `T{ .x = 1 }`) or declared without a value (`T x;`). The other fields are zeros, as before.

A constructor is a method named like the struct, without a result type. It is called like a function: `Circle(2.0)`. It receives an object already filled with the defaults and fills in the rest. No memory is allocated anywhere.

```zark run
struct Config {
    i64 width = 80;
    i64 height = 24;
    str name = "default";
}

struct Circle {
    f64 r;
    f64 area = 0.0;

    Circle(f64 radius) {
        r = radius;
        area = 3.0 * radius * radius;
    }
}

struct Window {
    Config cfg;
    i64 id = 1;
    Window(i64 n) { id = n; }
}

void main() {
    Config a;
    auto b = Config{ .width = 120 };
    println(a.width, a.height, a.name, b.width, b.height);
    const auto c = Circle(2.0);
    println(c.r, c.area);
    const auto w = Window(7);
    println(w.id, w.cfg.width);
}
```

Nested structs get their own defaults too. There are no destructors: release resources with `defer` (see [control flow](control-flow.md#defer-and-errdefer)).

## Interfaces

An interface describes a set of methods. A struct implements it if it has all those methods with the same types: there is no need to declare "inheritance".

```zark run
interface Shape {
    f64 area();
    void scale(f64 k);
}

struct Circle {
    f64 r;
    f64 area() { return 3.0 * r * r; }
    void scale(f64 k) { r *= k; }
}

struct Rect {
    f64 w;
    f64 h;
    f64 area() { return w * h; }
    void scale(f64 k) { w *= k; h *= k; }
}

f64 total(Shape[] shapes) {
    f64 sum = 0.0;
    for (auto s : shapes) { sum += s.area(); }
    return sum;
}

void main() {
    auto c = Circle{ .r = 2.0 };
    auto r = Rect{ .w = 3.0, .h = 4.0 };
    Shape[2] all = [&c, &r];
    println(total(all[..]));
    all[0].scale(2.0);
    println(total(all[..]), c.r);
}
```

A value of type `Shape` is a pair of two pointers: to the object and to the method table. The compiler builds it when `&c` is converted to `Shape`. A method call is one indirect load and one indirect call, like a function table in C. The object is neither copied nor allocated: the interface stores a pointer, so the object must outlive the interface. If a method is missing, the error says which one: `'Circle' does not implement 'Shape': missing method 'perimeter'`.

There is no implementation inheritance: shared code goes into a function or into a struct field.

## Operator overloading

For structs you can define `+ - * / %`, the comparisons `== != < <= > >=` and unary `-`. These are ordinary methods named `operator+` and so on, and the compiler turns `a + b` into `a.operator+(b)`. `!=` is taken from `==` if it is not defined.

```zark run
struct Vec2 {
    f64 x;
    f64 y;

    Vec2(f64 a, f64 b) { x = a; y = b; }
    Vec2 operator+(Vec2 o) const { return Vec2(x + o.x, y + o.y); }
    Vec2 operator*(f64 k) const { return Vec2(x * k, y * k); }
    Vec2 operator-() const { return Vec2(0.0 - x, 0.0 - y); }
    bool operator==(Vec2 o) const { return x == o.x && y == o.y; }
}

void main() {
    const auto a = Vec2(1.0, 2.0);
    const auto b = a + a * 2.0;
    const auto n = -a;
    println(b.x, b.y, n.x, a == b, a != b);
}
```

The operators `[]`, `()`, `->`, `<<` and assignment cannot be overloaded: an action must be visible in the code.

## Generic structs and unions

Type parameters are written in angle brackets after the name: `struct Pair<A, B>`. The methods live inside, and the parameters need not be listed separately.

```zark run
struct Pair<A, B> {
    A first;
    B second;

    Pair<B, A> swap() {
        return Pair<B, A>{ .first = this->second, .second = this->first };
    }
}

void main() {
    const auto p = Pair<i64, str>{ .first = 1, .second = "one" };
    const auto q = p.swap();
    println(p);
    println(q);
}
```

For every combination of arguments the compiler makes a separate copy of the type. This is how `List<T>`, `Map<V>` and `Option<T>` from the [standard library](stdlib.md) work.

A stack struct with a fixed-size array and methods:

```zark run
struct Stack<T> {
    T[4] items;
    i64 n;

    void push(T v) {
        this->items[this->n] = v;
        this->n += 1;
    }

    T top() {
        return this->items[this->n - 1];
    }
}

void main() {
    auto s = Stack<i64>{};
    s.push(3);
    s.push(4);
    println(s.top(), s.n);
}
```

Constraints on the parameters are written as for functions: `struct Sorted<T: Ord> { ... }`. A violation is caught when the type is created.

## What next

- How to keep such values on the heap: [memory and allocators](memory.md), [collections](collections.md).
- How to return "a value or an error": [errors and optional values](errors-and-optionals.md).
