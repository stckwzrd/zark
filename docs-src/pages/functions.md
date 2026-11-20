---
title: Functions and closures
order: 15
section: Language
description: Declaring functions, parameters, returning values, generics with constraints, function pointers and closures in Vibe
---

## Declaring and calling

```vibe run
i64 add(i64 a, i64 b) {
    return a + b;
}

void greet(str name) {
    println("Hello, {name}!");
}

void main() {
    println(add(2, 3));
    greet("world");
}
```

The syntax is `ResultType name(Type parameter, ...) { body }`. The result comes before the name, as in C++. A function without a result is declared as `void`.

The order of declarations in a file does not matter: you can call a function declared further down. This also allows mutual recursion:

```vibe run
bool even(i64 n) {
    if (n == 0) { return true; }
    return odd(n - 1);
}

bool odd(i64 n) {
    if (n == 0) { return false; }
    return even(n - 1);
}

void main() {
    println(even(10), odd(7), even(7));
}
```

A trailing comma in the list of parameters and arguments is allowed, and so is wrapping lines inside the parentheses (see [lexical structure](lexical.md#end-of-a-statement)).

## Number and types of arguments

There must be exactly as many arguments as parameters. There are no default values and no overloading by the number of arguments.

```vibe error
i64 f(i64 a, i64 b) { return a; }

void main() {
    println(f(1));
}
```

The type of an argument is checked, but integers are widened implicitly:

```vibe run
i64 double(i64 x) { return x * 2; }

void main() {
    const u8 small = 21;
    println(double(small));
}
```

```vibe error
i32 double(i32 x) { return x * 2; }

void main() {
    const i64 big = 21;
    println(double(big));
}
```

## Parameters are passed by value

A function receives a copy. Structs and arrays are copied whole. A parameter can be changed inside the function, but that changes the copy: the caller does not see it.

To let a function change someone else's data, pass a **pointer** or a **slice**:

```vibe run
void bump(i64* p) {
    *p += 1;
}

void fill(i64[] xs, i64 v) {
    for (auto i : 0..xs.len) { xs[i] = v; }
}

void main() {
    auto n = 1;
    bump(&n);
    bump(&n);
    auto arr = [0, 0, 0];
    fill(arr[..], 7);
    println(n, arr);
}
```

A parameter declared with `const` cannot be assigned:

```vibe error
void f(const i64 x) {
    x = 5;
}

void main() {
    f(1);
}
```

## Returning a value

`return value` leaves the function. In a function without a result a plain `return` is enough.

```vibe run
void check(i64 x) {
    if (x > 0) {
        println("positive");
        return;
    }
    println("not positive");
}

void main() {
    check(1);
    check(-1);
}
```

The result of a function without a value cannot be used:

```vibe error
void f() { println("x"); }

void main() {
    const auto r = f();
}
```

> **Gotcha:** the compiler does not check that a function with a result returns a value on **all** paths. If control reaches the end of the body without a `return`, the result is undefined. Always end such a function with a `return`.

### Several results

There are no tuples. For several values, make a small struct:

```vibe run
struct DivMod { i64 q; i64 r; }

DivMod divmod(i64 a, i64 b) {
    return DivMod{ .q = a / b, .r = a % b };
}

void main() {
    const auto d = divmod(17, 5);
    println(d.q, d.r);
}
```

Or return the result through a pointer parameter, as in C.

## Recursion

```vibe run
i64 fact(i64 n) {
    if (n <= 1) { return 1; }
    return n * fact(n - 1);
}

i64 fib(i64 n) {
    if (n < 2) { return n; }
    return fib(n - 1) + fib(n - 2);
}

void main() {
    println(fact(10), fib(20));
}
```

There is no tail-call optimization: a call that is too deep will exhaust the stack.

## Errors and optional values

A result of the form `!T` means "a value or an error", and `?T` means "a value or nothing":

```vibe run
!i64 safe_div(i64 a, i64 b) {
    if (b == 0) { return error.DivByZero; }
    return a / b;
}

?i64 find(i64[] xs, i64 v) {
    for (auto [i, x] : xs) {
        if (x == v) { return i; }
    }
    return null;
}

void main() {
    println(safe_div(10, 2) catch -1, safe_div(1, 0) catch -1);
    println(find([4, 5, 6], 6) orelse -1, find([4], 9) orelse -1);
}
```

Described in detail on the page [errors and optional values](errors-and-optionals.md).

## Generics

A function with type parameters in `template<...>` creates a separate copy for every combination of types (monomorphization). There is no run-time overhead.

```vibe run
template<T> T first(T[] xs) {
    return xs[0];
}

template<A, B> u64 pair_size(A a, B b) {
    return sizeof(A) + sizeof(B);
}

template<T> T zero() {
    T z;
    return z;
}

void main() {
    const auto nums = [10, 20];
    const auto words = ["a", "b"];
    println(first(nums[..]), first(words[..]));
    println(first<i64>([7, 8]));
    println(pair_size(1, 2.0), pair_size<u8, i64>(1, 2));
    println(zero<i64>(), zero<f64>());
}
```

The type is inferred from the arguments. The array literal `[10, 20]` is not suitable for inferring `T[]`: first put it in a variable and take a slice `nums[..]`, or give the type explicitly. When there is nothing to infer from (as with `zero`) or you want to set it explicitly, write `name<Type>(...)`.

The body of a generic is checked at the **use**, not at the declaration, and only for the types actually used. So an unsuitable type produces an error inside the body:

```vibe error
template<T> T add(T a, T b) {
    return a + b;
}

void main() {
    println(add("a", "b"));
}
```

### Constraints

To make the error clear and to report it before the body is compiled, write a constraint: `T: Ord`.

| Constraint | Which types fit |
|---|---|
| `Eq` | numbers, `bool`, characters, enums, pointers, `str` (they have `==`); structs do not fit |
| `Ord` | numbers (they have `<`, `>`) |
| `Num` | numbers (they have arithmetic) |
| `Int` | integers |
| `Float` | `f32`, `f64` |

```vibe run
template<T: Ord> T largest(T a, T b) {
    if (a > b) { return a; }
    return b;
}

template<T: Num> T sum(T[] xs) {
    T t;
    for (auto x : xs) { t = t + x; }
    return t;
}

void main() {
    println(largest(3, 9), largest(2.5, 1.5));
    const auto ints = [1, 2, 3];
    const auto fs = [0.5, 0.25];
    println(sum(ints[..]), sum(fs[..]));
}
```

The body of the function is checked against the declared constraint right at the declaration: an operator that the constraint does not provide (`<` with `T: Eq`, `+` with `T: Ord`) is an error even if nobody calls the function. A call that violates the constraint is reported at the call:

```vibe error
template<T: Ord> T largest(T a, T b) {
    if (a > b) { return a; }
    return b;
}

void main() {
    println(largest("a", "b"));
}
```

Strings do not satisfy `Ord`: `str` cannot be ordered (see [operators](operators.md#comparisons)).

The standard library already has such functions: `min`, `max`, `abs`, `swap`, `sort` (see the [reference](stdlib.md)).

## Function pointers

The name of a function can be passed as a value. The type is written as `fn(Parameters) -> Result`.

```vibe run
i64 inc(i64 x) { return x + 1; }
i64 dbl(i64 x) { return x * 2; }

i64 apply_twice(fn(i64) -> i64 f, i64 x) {
    return f(f(x));
}

void main() {
    println(apply_twice(inc, 5), apply_twice(dbl, 5));
    fn(i64) -> i64 op = inc;
    println(op(1));
    op = dbl;
    println(op(1));
}
```

Such a value is just an address. It can be `null`:

```vibe run
void main() {
    fn(i64) -> i64 f = null;
    println(f == null);
}
```

Calling through `null` crashes the program, so check before calling.

A typical example is the comparison in a sort:

```vibe run
void sort_by(i64[] xs, fn(i64, i64) -> bool less) {
    for (auto i : 0..xs.len) {
        for (auto j : i + 1..xs.len) {
            if (less(xs[j], xs[i])) { swap(&xs[i], &xs[j]); }
        }
    }
}

bool desc(i64 a, i64 b) { return a > b; }

void main() {
    auto v = [3, 1, 2];
    sort_by(v[..], desc);
    println(v);
}
```

## Closures

An ordinary function does not know the variables around it. A closure remembers them, but does so **explicitly**: the list of captured variables is written in square brackets before the parameters, as in C++: `[&k](i64 x) -> i64 { ... }`.

```vibe run
i64 apply(fn[](i64) -> i64 f, i64 x) {
    return f(x);
}

void main() {
    const auto k = 10;
    const auto add = [&k](i64 x) -> i64 {
        return x + k;
    };
    println(apply(add, 1), apply(add, 2));
}
```

The type of a closure is `fn[](A) -> R` (with empty square brackets), which differs from the type of an ordinary function `fn(A) -> R`.

### Capture by reference

The variables in the list are captured **by reference**: the closure stores pointers to them, so it sees the current values and can change them.

```vibe run
void main() {
    auto total = 0;
    const auto acc = [&total](i64 x) {
        total += x;
    };
    acc(5);
    acc(7);
    println(total);

    auto n = 1;
    const auto show = [&n]() {
        println("n = {n}");
    };
    show();
    n = 99;
    show();
}
```

The closure's context lives on the stack of the function where the literal is written. A closure costs one indirect call, and nothing is allocated on the heap.

> **Gotcha:** a closure cannot be returned from a function: after the return the stack is freed, and the closure would refer to garbage. The result "works" but prints random numbers:
>
> ```vibe
> fn[](i64) -> i64 make() {
>     const auto k = 5;
>     return [&k](i64 x) -> i64 { return x + k; };
> }
> ```
>
> Pass a closure **down** (into the called function), but not **up**.

### Capture without a list does not work

If you forget a variable in the `[...]` list, you get an error:

```vibe error fragment
const auto k = 3;
const auto f = [](i64 x) -> i64 { return x + k; };
```

### A closure and an ordinary function are different types

A parameter of type `fn[](i64) -> i64` accepts only a closure. An ordinary function cannot be passed there, and the other way round:

```vibe error
i64 apply(fn[](i64) -> i64 f, i64 x) { return f(x); }
i64 dbl(i64 x) { return x * 2; }

void main() {
    println(apply(dbl, 5));
}
```

If your function needs only callable values without capture, accept `fn(A) -> R`. If you need closures, accept `fn[](A) -> R`. A closure with an empty list `[](i64 x) -> i64 { ... }` is also allowed.

## Methods

A function inside a `struct` is a method of the type. They are described on the page about [structs](structs-unions-enums.md#methods).

## `extern` and `export`

`extern` declares a function from C, and `export` makes a Vibe function visible to C under its own name. Described in detail in [interoperating with C](c-interop.md).

## Standard library names

The functions of the standard library live in the same namespace as yours. You cannot declare your own `min`, `max`, `abs`, `sort`, `run`, `env` and so on: you will get a duplicate error.

```vibe error
i64 max(i64 a, i64 b) { return a; }

void main() {
    println(max(1, 2));
}
```

Choose other names. The full list is in the [reference](stdlib.md).

## What next

- Structs and methods: [structs, unions and enums](structs-unions-enums.md).
- Everything about errors: [errors and optional values](errors-and-optionals.md).
