---
title: Recipes and finished programs
order: 41
section: Reference
description: Complete programs in Zark: FizzBuzz, a word counter, a calculator, a linked list, a tree, a state machine, argument parsing and more
---

Every recipe is a whole program that you can copy and run: `zark run main.zk`. The output under the code comes from a real run.

## FizzBuzz

```zark run
void main() {
    for (auto i : 1..16) {
        if (i % 15 == 0) {
            println("FizzBuzz");
        } else if (i % 3 == 0) {
            println("Fizz");
        } else if (i % 5 == 0) {
            println("Buzz");
        } else {
            println(i);
        }
    }
}
```

## Prime numbers (the sieve of Eratosthenes)

```zark run
!void main() {
    const auto n = 50;
    const auto a = c_allocator();
    const auto sieve = a.alloc<bool>(n + 1)?;
    defer a.free(sieve);

    for (auto i : 2..n + 1) { sieve[i] = true; }
    auto i = 2;
    while (i * i <= n) {
        if (sieve[i]) {
            auto j = i * i;
            while (j <= n) {
                sieve[j] = false;
                j += i;
            }
        }
        i += 1;
    }
    auto count = 0;
    for (auto k : 2..n + 1) {
        if (sieve[k]) {
            print(k, "");
            count += 1;
        }
    }
    println();
    println("total", count);
}
```

The memory is zeroed, so the `bool` array starts as `false`.

## Fibonacci numbers without recursion

```zark run
i64 fib(i64 n) {
    auto a = 0;
    auto b = 1;
    for (auto i : 0..n) {
        const auto t = a + b;
        a = b;
        b = t;
    }
    return a;
}

void main() {
    for (auto n : [0, 1, 2, 10, 50, 90]) {
        println("fib({n}) = {fib(n)}");
    }
}
```

## Greatest common divisor and least common multiple

```zark run
i64 gcd(i64 a, i64 b) {
    auto x = a;
    auto y = b;
    while (y != 0) {
        const auto t = x % y;
        x = y;
        y = t;
    }
    return x;
}

i64 lcm(i64 a, i64 b) {
    return a / gcd(a, b) * b;
}

void main() {
    println(gcd(84, 36), lcm(4, 6));
}
```

## Reversing a string and palindromes

```zark run
!str reverse(Allocator a, str s) {
    const auto out = a.alloc<u8>(s.len)?;
    for (auto [i, c] : s) { out[s.len - 1 - i] = c; }
    return out;
}

bool is_palindrome(str s) {
    auto i = 0;
    auto j = s.len - 1;
    while (i < j) {
        if (s[i] != s[j]) { return false; }
        i += 1;
        j -= 1;
    }
    return true;
}

!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();
    println(reverse(a, "hello")?);
    println(is_palindrome("level"), is_palindrome("zark"));
}
```

It works on bytes, so everything is right for ASCII. Multi-byte letters are not reversed correctly this way.

## A word counter

```zark run
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    const auto text = "to be or not to be that is the question to be";
    auto counts = Map<i64>::init(a);
    auto order = List<str>::init(a);

    auto start = 0;
    for (auto i : 0..text.len + 1) {
        if (i == text.len || text[i] == ' ') {
            const auto w = text[start..i];
            if (!counts.has(w)) { order.push(w)?; }
            counts.put(w, (counts.get(w) catch 0) + 1)?;
            start = i + 1;
        }
    }
    for (auto w : order) {
        println("{w}: {counts.get(w)?}");
    }
}
```

The list `order` remembers the order in which the words appeared, because the traversal order of a `Map` is undefined.

## A calculator in reverse Polish notation

It shows errors, a stack and parsing a string:

```zark run
!i64 eval(Allocator a, str src) {
    auto st = List<i64>::init(a);
    defer st.deinit();
    auto start = 0;
    for (auto i : 0..src.len + 1) {
        if (i < src.len && src[i] != ' ') { continue; }
        const auto tok = src[start..i];
        start = i + 1;
        if (tok.len == 0) { continue; }
        if (tok == "+" || tok == "-" || tok == "*" || tok == "/") {
            const auto b = st.pop() catch return error.StackUnderflow;
            const auto x = st.pop() catch return error.StackUnderflow;
            auto r = 0;
            if (tok == "+") { r = x + b; }
            if (tok == "-") { r = x - b; }
            if (tok == "*") { r = x * b; }
            if (tok == "/") {
                if (b == 0) { return error.DivByZero; }
                r = x / b;
            }
            st.push(r)?;
        } else {
            st.push(parse_int(tok)?)?;
        }
    }
    const auto result = st.pop() catch return error.StackUnderflow;
    return result;
}

void main() {
    const auto a = c_allocator();
    const auto exprs = ["3 4 +", "2 3 4 * +", "10 2 /", "1 0 /", "1 +", "2 x +"];
    for (auto e : exprs) {
        const auto r = eval(a, e) catch |err| {
            println("{e} -> error {err}");
            continue;
        };
        println("{e} -> {r}");
    }
}
```

## A linked list

The nodes are allocated from an arena, and there is no need to clean them up one by one:

```zark run
struct Node {
    i64 val;
    Node* next;
}

struct Stack {
    Node* head;
    Allocator a;

    !void push(i64 v) {
        const auto n = this->a.create<Node>()?;
        n.val = v;
        n.next = this->head;
        this->head = n;
    }

    ?i64 pop() {
        if (this->head == null) { return null; }
        const auto n = this->head;
        this->head = n.next;
        return n.val;
    }
}

!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    auto s = Stack{ .head = null, .a = arena.allocator() };
    for (auto i : 1..5) { s.push(i * 11)?; }
    while (true) {
        const auto v = s.pop() orelse break;
        println(v);
    }
}
```

## A binary search tree

```zark run
struct Tree {
    i64 key;
    Tree* left;
    Tree* right;
}

!Tree* insert(Allocator a, Tree* root, i64 key) {
    if (root == null) {
        const auto n = a.create<Tree>()?;
        n.key = key;
        return n;
    }
    if (key < root.key) {
        root.left = insert(a, root.left, key)?;
    } else {
        root.right = insert(a, root.right, key)?;
    }
    return root;
}

void walk(Tree* t) {
    if (t == null) { return; }
    walk(t.left);
    print(t.key, "");
    walk(t.right);
}

i64 height(Tree* t) {
    if (t == null) { return 0; }
    return 1 + max(height(t.left), height(t.right));
}

!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();
    Tree* root = null;
    for (auto k : [50, 30, 70, 20, 40, 60, 80, 35]) {
        root = insert(a, root, k)?;
    }
    walk(root);
    println();
    println("height", height(root));
}
```

## A state machine

The state is an `enum`, and a transition is a `match`:

```zark run
enum Light { Red, Green, Yellow }

Light next(Light l) {
    return match l {
        .Red => .Green,
        .Green => .Yellow,
        .Yellow => .Red,
    }
}

i64 seconds(Light l) {
    return match l {
        .Red => 30,
        .Green => 25,
        .Yellow => 5,
    }
}

void main() {
    Light l = .Red;
    auto t = 0;
    for (auto i : 0..5) {
        println("{l} for {seconds(l)} s, t = {t}");
        t += seconds(l);
        l = next(l);
    }
}
```

## A tokenizer on a union

```zark run
union Token {
    i64 Num;
    Plus;
    Minus;
    Star;
    LParen;
    RParen;
}

!List<Token> tokenize(Allocator a, str src) {
    auto out = List<Token>::init(a);
    auto i = 0;
    while (i < src.len) {
        const auto c = src[i];
        if (c == ' ') {
            i += 1;
        } else if (is_digit(c)) {
            auto n = 0;
            while (i < src.len && is_digit(src[i])) {
                n = n * 10 + (src[i] - '0') as i64;
                i += 1;
            }
            out.push(.Num(n))?;
        } else {
            match c {
                '+' => out.push(.Plus)?;
                '-' => out.push(.Minus)?;
                '*' => out.push(.Star)?;
                '(' => out.push(.LParen)?;
                ')' => out.push(.RParen)?;
                _ => return error.BadChar;
            }
            i += 1;
        }
    }
    return out;
}

!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto toks = tokenize(arena.allocator(), "12 + (3*45) - 6")?;
    for (auto t : toks) {
        match t {
            .Num(n) => print("Num({n})", "");
            .Plus => print("+", "");
            .Minus => print("-", "");
            .Star => print("*", "");
            .LParen => print("(", "");
            .RParen => print(")", "");
        }
    }
    println();
    println(toks.len);
    const auto bad = tokenize(arena.allocator(), "1 $ 2") catch |e| {
        println("error: {e}");
        return;
    };
    println(bad.len);
}
```

## A matrix: multiplication

```zark run
const auto N = 3;

i64[N][N] mul(i64[N][N] a, i64[N][N] b) {
    i64[N][N] c;
    for (auto i : 0..N) {
        for (auto j : 0..N) {
            for (auto k : 0..N) {
                c[i][j] += a[i][k] * b[k][j];
            }
        }
    }
    return c;
}

void main() {
    const auto a = [[1, 2, 3], [4, 5, 6], [7, 8, 9]];
    const auto id = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];
    const auto sq = mul(a, a);
    println(sq);
    println(mul(a, id));
}
```

Arrays are passed and returned **by value**: the function receives copies. Arrays cannot be compared with `==`; compare element by element.

## Reading and processing a file

```zark run
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    write_file("nums.txt", "10\n20\nabc\n30\n")?;
    defer _ = remove("nums.txt");

    const auto text = read_file(a, "nums.txt")?;
    auto sum = 0;
    auto bad = 0;
    auto start = 0;
    for (auto i : 0..text.len) {
        if (text[i] == '\n') {
            const auto line = text[start..i];
            start = i + 1;
            sum += parse_int(line) catch {
                bad += 1;
                continue;
            }
        }
    }
    println("sum {sum}, bad lines {bad}");
}
```

## Command-line arguments

```zark run with=allow-fail
void main() {
    if (arg_count() < 2) {
        println("usage: program <name>");
        return;
    }
    println("hello, {arg(1)}");
}
```

Running `zark run main.zk -- World` passes `World` as `arg(1)`. Number 0 is the program path.

## A timer

```zark run
i64 work(i64 n) {
    auto s = 0;
    for (auto i : 0..n) { s += i % 7; }
    return s;
}

void main() {
    const auto t0 = now_ns();
    const auto r = work(10000000);
    const auto ms = (now_ns() - t0) as f64 / 1000000.0;
    println("result {r}, time measured: {ms >= 0.0}");
}
```

The time is printed less often than it is checked: it changes from run to run.

## Calling an external command

```zark run
!void main() {
    const auto code = run(c_allocator(), ["/bin/sh", "-c", "echo from the shell; exit 2"])?;
    println("exit code", code);
}
```

## What next

- If an example does not build or behaves strangely: [pitfalls and FAQ](gotchas.md).
- More about each function: [reference](stdlib.md).
