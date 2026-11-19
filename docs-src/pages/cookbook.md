---
title: Рецепты и готовые программы
order: 41
section: Справочник
description: Законченные программы на Vibe: FizzBuzz, счётчик слов, калькулятор, связный список, дерево, конечный автомат, разбор аргументов и другое
---

Каждый рецепт — целая программа, которую можно скопировать и запустить: `vibe run main.vibe`. Вывод под кодом получен настоящим запуском.

## FizzBuzz

```vibe run
fn main() {
    for i in 1..16 {
        if i % 15 == 0 {
            println("FizzBuzz")
        } else if i % 3 == 0 {
            println("Fizz")
        } else if i % 5 == 0 {
            println("Buzz")
        } else {
            println(i)
        }
    }
}
```

## Простые числа (решето Эратосфена)

```vibe run
fn main() !void {
    let n = 50
    let a = c_allocator()
    let sieve = a.alloc[bool](n + 1)?
    defer a.free(sieve)

    for i in 2..n + 1 { sieve[i] = true }
    var i = 2
    while i * i <= n {
        if sieve[i] {
            var j = i * i
            while j <= n {
                sieve[j] = false
                j += i
            }
        }
        i += 1
    }
    var count = 0
    for k in 2..n + 1 {
        if sieve[k] {
            print(k, "")
            count += 1
        }
    }
    println()
    println("всего", count)
}
```

Память нулевая, поэтому массив `bool` начинается с `false`.

## Числа Фибоначчи без рекурсии

```vibe run
fn fib(n: i64) i64 {
    var a = 0
    var b = 1
    for i in 0..n {
        let t = a + b
        a = b
        b = t
    }
    return a
}

fn main() {
    for n in [0, 1, 2, 10, 50, 90] {
        println("fib({n}) = {fib(n)}")
    }
}
```

## Наибольший общий делитель и НОК

```vibe run
fn gcd(a: i64, b: i64) i64 {
    var x = a
    var y = b
    while y != 0 {
        let t = x % y
        x = y
        y = t
    }
    return x
}

fn lcm(a: i64, b: i64) i64 {
    return a / gcd(a, b) * b
}

fn main() {
    println(gcd(84, 36), lcm(4, 6))
}
```

## Разворот строки и палиндромы

```vibe run
fn reverse(a: Allocator, s: str) !str {
    let out = a.alloc[u8](s.len)?
    for i, c in s { out[s.len - 1 - i] = c }
    return out
}

fn is_palindrome(s: str) bool {
    var i = 0
    var j = s.len - 1
    while i < j {
        if s[i] != s[j] { return false }
        i += 1
        j -= 1
    }
    return true
}

fn main() !void {
    var arena = Arena.init(c_allocator())
    defer arena.deinit()
    let a = arena.allocator()
    println(reverse(a, "hello")?)
    println(is_palindrome("level"), is_palindrome("vibe"))
}
```

Работа идёт с байтами, поэтому для ASCII всё верно. Русские буквы (два байта) таким способом не переворачиваются.

## Счётчик слов

```vibe run
fn main() !void {
    var arena = Arena.init(c_allocator())
    defer arena.deinit()
    let a = arena.allocator()

    let text = "to be or not to be that is the question to be"
    var counts = Map[i64].init(a)
    var order = List[str].init(a)

    var start = 0
    for i in 0..text.len + 1 {
        if i == text.len || text[i] == ' ' {
            let w = text[start..i]
            if !counts.has(w) { order.push(w)? }
            counts.put(w, (counts.get(w) catch 0) + 1)?
            start = i + 1
        }
    }
    for w in order {
        println("{w}: {counts.get(w)?}")
    }
}
```

Список `order` запоминает порядок появления слов, потому что порядок обхода `Map` не определён.

## Калькулятор в обратной польской записи

Показывает ошибки, стек и разбор строки:

```vibe run
fn eval(a: Allocator, src: str) !i64 {
    var st = List[i64].init(a)
    defer st.deinit()
    var start = 0
    for i in 0..src.len + 1 {
        if i < src.len && src[i] != ' ' { continue }
        let tok = src[start..i]
        start = i + 1
        if tok.len == 0 { continue }
        if tok == "+" || tok == "-" || tok == "*" || tok == "/" {
            let b = st.pop() catch return error.StackUnderflow
            let x = st.pop() catch return error.StackUnderflow
            var r = 0
            if tok == "+" { r = x + b }
            if tok == "-" { r = x - b }
            if tok == "*" { r = x * b }
            if tok == "/" {
                if b == 0 { return error.DivByZero }
                r = x / b
            }
            st.push(r)?
        } else {
            st.push(parse_int(tok)?)?
        }
    }
    let result = st.pop() catch return error.StackUnderflow
    return result
}

fn main() {
    let a = c_allocator()
    let exprs = ["3 4 +", "2 3 4 * +", "10 2 /", "1 0 /", "1 +", "2 x +"]
    for e in exprs {
        let r = eval(a, e) catch |err| {
            println("{e} -> ошибка {err}")
            continue
        }
        println("{e} -> {r}")
    }
}
```

## Связный список

Узлы выделяются из арены, и очищать их по одному не нужно:

```vibe run
struct Node {
    val: i64
    next: *Node
}

struct Stack {
    head: *Node
    a: Allocator
}

impl Stack {
    fn push(self, v: i64) !void {
        let n = self.a.create[Node]()?
        n.val = v
        n.next = self.head
        self.head = n
    }

    fn pop(self) ?i64 {
        if self.head == null { return null }
        let n = self.head
        self.head = n.next
        return n.val
    }
}

fn main() !void {
    var arena = Arena.init(c_allocator())
    defer arena.deinit()
    var s = Stack{ head: null, a: arena.allocator() }
    for i in 1..5 { s.push(i * 11)? }
    while true {
        let v = s.pop() orelse break
        println(v)
    }
}
```

## Двоичное дерево поиска

```vibe run
struct Tree {
    key: i64
    left: *Tree
    right: *Tree
}

fn insert(a: Allocator, root: *Tree, key: i64) !*Tree {
    if root == null {
        let n = a.create[Tree]()?
        n.key = key
        return n
    }
    if key < root.key {
        root.left = insert(a, root.left, key)?
    } else {
        root.right = insert(a, root.right, key)?
    }
    return root
}

fn walk(t: *Tree) {
    if t == null { return }
    walk(t.left)
    print(t.key, "")
    walk(t.right)
}

fn height(t: *Tree) i64 {
    if t == null { return 0 }
    return 1 + max(height(t.left), height(t.right))
}

fn main() !void {
    var arena = Arena.init(c_allocator())
    defer arena.deinit()
    let a = arena.allocator()
    var root: *Tree = null
    for k in [50, 30, 70, 20, 40, 60, 80, 35] {
        root = insert(a, root, k)?
    }
    walk(root)
    println()
    println("высота", height(root))
}
```

## Конечный автомат

Состояние — `enum`, переход — `match`:

```vibe run
enum Light { Red, Green, Yellow }

fn next(l: Light) Light {
    return match l {
        .Red => .Green,
        .Green => .Yellow,
        .Yellow => .Red,
    }
}

fn seconds(l: Light) i64 {
    return match l {
        .Red => 30,
        .Green => 25,
        .Yellow => 5,
    }
}

fn main() {
    var l: Light = .Red
    var t = 0
    for i in 0..5 {
        println("{l} на {seconds(l)} с, t = {t}")
        t += seconds(l)
        l = next(l)
    }
}
```

## Токенизатор на union

```vibe run
union Token {
    Num: i64
    Plus
    Minus
    Star
    LParen
    RParen
}

fn tokenize(a: Allocator, src: str) !List[Token] {
    var out = List[Token].init(a)
    var i = 0
    while i < src.len {
        let c = src[i]
        if c == ' ' {
            i += 1
        } else if is_digit(c) {
            var n = 0
            while i < src.len && is_digit(src[i]) {
                n = n * 10 + (src[i] - '0') as i64
                i += 1
            }
            out.push(.Num(n))?
        } else {
            match c {
                '+' => out.push(.Plus)?
                '-' => out.push(.Minus)?
                '*' => out.push(.Star)?
                '(' => out.push(.LParen)?
                ')' => out.push(.RParen)?
                _ => return error.BadChar
            }
            i += 1
        }
    }
    return out
}

fn main() !void {
    var arena = Arena.init(c_allocator())
    defer arena.deinit()
    let toks = tokenize(arena.allocator(), "12 + (3*45) - 6")?
    for t in toks {
        match t {
            .Num(n) => print("Num({n})", "")
            .Plus => print("+", "")
            .Minus => print("-", "")
            .Star => print("*", "")
            .LParen => print("(", "")
            .RParen => print(")", "")
        }
    }
    println()
    println(toks.len)
    let bad = tokenize(arena.allocator(), "1 $ 2") catch |e| {
        println("ошибка: {e}")
        return
    }
    println(bad.len)
}
```

## Матрица: умножение

```vibe run
const N = 3

fn mul(a: [N][N]i64, b: [N][N]i64) [N][N]i64 {
    var c: [N][N]i64
    for i in 0..N {
        for j in 0..N {
            for k in 0..N {
                c[i][j] += a[i][k] * b[k][j]
            }
        }
    }
    return c
}

fn main() {
    let a = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
    let id = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    let sq = mul(a, a)
    println(sq)
    println(mul(a, id))
}
```

Массивы передаются и возвращаются **по значению**: функция получает копии. Сравнивать массивы через `==` нельзя, сравнивайте по элементам.

## Чтение и обработка файла

```vibe run
fn main() !void {
    var arena = Arena.init(c_allocator())
    defer arena.deinit()
    let a = arena.allocator()

    write_file("nums.txt", "10\n20\nабв\n30\n")?
    defer _ = remove("nums.txt")

    let text = read_file(a, "nums.txt")?
    var sum = 0
    var bad = 0
    var start = 0
    for i in 0..text.len {
        if text[i] == '\n' {
            let line = text[start..i]
            start = i + 1
            sum += parse_int(line) catch {
                bad += 1
                continue
            }
        }
    }
    println("сумма {sum}, плохих строк {bad}")
}
```

## Аргументы командной строки

```vibe run with=allow-fail
fn main() {
    if arg_count() < 2 {
        println("использование: программа <имя>")
        return
    }
    println("привет, {arg(1)}")
}
```

Запуск через `vibe run main.vibe -- Мир` передаёт `Мир` как `arg(1)`. Номер 0 — путь программы.

## Таймер

```vibe run
fn work(n: i64) i64 {
    var s = 0
    for i in 0..n { s += i % 7 }
    return s
}

fn main() {
    let t0 = now_ns()
    let r = work(10000000)
    let ms = (now_ns() - t0) as f64 / 1000000.0
    println("результат {r}, время измерено: {ms >= 0.0}")
}
```

Время печатают реже, чем проверяют: оно меняется от запуска к запуску.

## Вызов внешней команды

```vibe run
fn main() !void {
    let code = run(c_allocator(), ["/bin/sh", "-c", "echo из shell; exit 2"])?
    println("код выхода", code)
}
```

## Что дальше

- Если пример не собирается или ведёт себя странно: [ловушки и FAQ](gotchas.md).
- Подробнее про каждую функцию: [справочник](stdlib.md).
