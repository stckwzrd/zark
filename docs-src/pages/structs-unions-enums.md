---
title: Структуры, union и enum
order: 16
section: Язык
description: struct, impl и методы, enum, tagged union, дженерик-структуры, раскладка в памяти и разбор через match
---

Три способа описать собственный тип данных:

| | Что хранит | Пример |
|---|---|---|
| `struct` | **все** поля сразу | точка с `x` и `y` |
| `enum` | один из набора **имён** | направление: север, юг |
| `union` | один из **вариантов**, каждый со своими данными | фигура: круг с радиусом или прямоугольник |

## `struct`

```vibe run
struct Point {
    x: i64
    y: i64
}

fn main() {
    let p = Point{ x: 3, y: 4 }
    println(p.x, p.y)
    println(p)
}
```

Поля пишутся через запятую или с новой строки (запятая в конце строки необязательна). Тип структуры печатается как `Имя{ поле: значение }`.

Все структуры раскладываются в памяти так же, как в C: поля идут по порядку, между ними добавляется выравнивание. Размер можно узнать через `sizeof`:

```vibe run
struct Small { a: u8, b: u8, c: u8 }
struct Padded { a: u8, b: i64, c: u8 }

fn main() {
    println(sizeof(Small), sizeof(Padded), alignof(Padded))
}
```

Порядок полей влияет на размер: сначала крупные поля, потом мелкие, и структура будет компактнее.

### Литерал структуры

Литерал пишется как `Имя{ поле: значение, ... }`. Он распознаётся, только если имя типа начинается с **заглавной** буквы.

Должны быть перечислены **все** поля. Чтобы обнулить остальные, добавьте `..`:

```vibe run
struct Config {
    width: i64
    height: i64
    title: str
    visible: bool
}

fn main() {
    let a = Config{ width: 800, height: 600, title: "окно", visible: true }
    let b = Config{ width: 100, .. }
    let c = Config{ .. }
    println(a)
    println(b)
    println(c.width, c.title.len)
}
```

Пропуск поля и опечатка в его имени — ошибки компиляции:

```vibe error
struct P { x: i64, y: i64 }

fn main() {
    let p = P{ x: 1 }
}
```

```vibe error
struct P { x: i64, y: i64 }

fn main() {
    let p = P{ x: 1, y: 2, w: 3 }
}
```

Значений по умолчанию в объявлении поля нет. Если нужны разумные умолчания, пишите функцию `new`.

### Структуры копируются

Присваивание и передача в функцию копируют все поля:

```vibe run
struct P { x: i64, y: i64 }

fn main() {
    var a = P{ x: 1, y: 2 }
    var b = a
    b.x = 99
    println(a.x, b.x)
}
```

Чтобы работать с одним объектом, передавайте указатель `*P` (поля через него читаются прямо через точку).

### Вложенные структуры и массивы

```vibe run
struct Point { x: i64, y: i64 }
struct Line { a: Point, b: Point }
struct Poly { pts: [3]Point, n: i64 }

fn main() {
    let l = Line{ a: Point{ x: 0, y: 0 }, b: Point{ x: 3, y: 4 } }
    println(l.b.x, l)
    var poly = Poly{ .. }
    poly.pts[1].x = 5
    poly.n = 2
    println(poly)
}
```

### Ссылка на себя

Структура не может содержать **саму себя** по значению, но может содержать указатель на себя:

```vibe run
struct Node {
    val: i64
    next: *Node
}

fn main() {
    var a = Node{ val: 1, next: null }
    var b = Node{ val: 2, next: &a }
    println(b.next.val, a.next == null)
}
```

### Сравнение

`==` для структур не определён. Сравнивайте поля:

```vibe error
struct A { x: i64 }

fn main() {
    let a = A{ x: 1 }
    println(a == a)
}
```

## `impl` — методы

Функции, привязанные к типу, лежат в блоке `impl Тип { ... }`. Блок можно разбить на несколько `impl` для одного типа.

```vibe run
struct Counter { n: i64 }

impl Counter {
    fn new() Self {
        return Self{ n: 0 }
    }

    fn inc(self) {
        self.n += 1
    }

    fn get(self) i64 {
        return self.n
    }
}

fn main() {
    var c = Counter.new()
    c.inc()
    c.inc()
    println(c.get())
    let p = &c
    p.inc()
    println(p.get(), c.n)
}
```

- `Self` внутри `impl` — это сам тип.
- Функция **без** `self` — статическая: вызывается как `Тип.имя(...)`.
- `self` без типа означает `self: *Self`: метод получает **указатель** и может менять поля. Вызывать его можно и у значения, и у указателя.
- `self: Self` — метод получает **копию**; изменения не видны снаружи.

```vibe run
struct V { n: i64 }

impl V {
    fn by_ptr(self) { self.n += 1 }
    fn by_val(self: Self) i64 {
        var c = self
        c.n += 100
        return c.n
    }
}

fn main() {
    var v = V{ n: 1 }
    v.by_ptr()
    println(v.by_val(), v.n)
}
```

> **Ловушка.** Метод с `self` меняет объект даже тогда, когда он объявлен через `let`: компилятор отдаёт методу указатель и не проверяет изменяемость. Проверка срабатывает только на прямом присваивании `p.x = ...`. Если объект не должен меняться, не вызывайте на нём мутирующих методов.

## `enum`

Перечисление — набор имён. Значение хранится как целое число (порядковый номер варианта с нуля).

```vibe run
enum Color { Red, Green, Blue }

fn main() {
    let c: Color = .Green
    println(c, Color.Blue, c == .Green, c != .Red)
    println(Color.Blue as i64, 1 as Color)
}
```

Литерал `.Имя` работает, когда тип известен из контекста: у `let c: Color`, у параметра функции, у `return`, у второго операнда сравнения. Если контекста нет, пишите `Color.Green`.

Номера варианта задавать (`A = 5`) нельзя: всегда 0, 1, 2 и т. д.

Перебрать все значения можно через преобразование из целого:

```vibe run
enum Day { Mon, Tue, Wed }

fn main() {
    for i in 0..3 {
        let d = i as Day
        println(i, d)
    }
}
```

> **Ловушка.** Преобразование `число as Enum` не проверяет диапазон: `7 as Day` даст значение «не из списка», а `match` на нём не найдёт совпадения.

### `match` по enum

```vibe run
enum Dir { North, East, South, West }

fn turn(d: Dir) Dir {
    return match d {
        .North => .East,
        .East => .South,
        .South => .West,
        .West => .North,
    }
}

fn main() {
    var d: Dir = .North
    for i in 0..5 {
        println(d)
        d = turn(d)
    }
}
```

Как `match`-выражение он обязан покрывать все варианты. Подробнее: [управление потоком](control-flow.md#match).

### Методы у enum

```vibe run
enum Level { Low, High }

impl Level {
    fn label(self: Self) str {
        return match self {
            .Low => "низкий",
            .High => "высокий",
        }
    }

    fn flip(self: Self) Self {
        return match self {
            .Low => .High,
            .High => .Low,
        }
    }
}

fn main() {
    let l: Level = .Low
    println(l.label(), l.flip().label())
}
```

Если метод принимает `self` (указатель), внутри разыменовывайте: `match *self { ... }`.

## `union` — тип-сумма (tagged union)

Union хранит **один из вариантов**, и вместе с ним — тег, который говорит какой. У варианта может быть payload (данные) любого типа, а может не быть.

```vibe run
union Shape {
    Circle: f64
    Rect: i64
    Empty
}

fn main() {
    let a: Shape = .Circle(2.5)
    let b = Shape.Rect(4)
    let c: Shape = .Empty
    println(a, b, c)
}
```

Раскладка: `{ i32 tag, payload }`, размер определяется самым большим вариантом.

```vibe run
union V { I: i64, F: f64, S: str, N }

fn main() {
    println(sizeof(V))
}
```

### Разбор через `match`

Образец `.Вариант(имя)` привязывает payload. Привязанное значение — копия, только для чтения.

```vibe run
union Shape {
    Circle: f64
    Rect: i64
    Empty
}

fn area(s: Shape) f64 {
    return match s {
        .Circle(r) => 3.14 * r * r,
        .Rect(w) => w as f64 * w as f64,
        .Empty => 0.0,
    }
}

fn main() {
    println(area(.Circle(1.0)), area(.Rect(3)), area(.Empty))
}
```

Проверка одного варианта без разбора — `is`:

```vibe run
union Msg { Text: str, Quit }

fn main() {
    let m: Msg = .Quit
    println(m is .Quit, m is .Text)
}
```

### Union как состояние и результат

Union удобен там, где значение бывает разных видов. Например, разбор токена:

```vibe run
union Token {
    Num: i64
    Plus
    Minus
    End
}

fn show(t: Token) {
    match t {
        .Num(n) => println("число {n}")
        .Plus => println("+")
        .Minus => println("-")
        .End => println("конец")
    }
}

fn main() {
    let toks = [Token.Num(1), Token.Plus, Token.Num(2), Token.End]
    for t in toks { show(t) }
}
```

### Методы у union

```vibe run
union Shape { Circle: f64, Rect: i64 }

impl Shape {
    fn circle(r: f64) Self {
        return Self.Circle(r)
    }

    fn area(self) f64 {
        return match *self {
            .Circle(r) => r * r * 3.0,
            .Rect(w) => w as f64,
        }
    }
}

fn main() {
    let s = Shape.circle(2.0)
    println(s.area())
}
```

## Дженерик-структуры и union

Параметры типа пишутся в квадратных скобках после имени. В `impl` их перечисляют заново.

```vibe run
struct Pair[A, B] {
    first: A
    second: B
}

impl Pair[A, B] {
    fn swap(self) Pair[B, A] {
        return Pair[B, A]{ first: self.second, second: self.first }
    }
}

fn main() {
    let p = Pair[i64, str]{ first: 1, second: "один" }
    let q = p.swap()
    println(p)
    println(q)
}
```

Для каждой комбинации аргументов компилятор делает отдельную копию типа. Так устроены `List[T]`, `Map[V]` и `Option[T]` из [стандартной библиотеки](stdlib.md).

Структура-стек с массивом фиксированного размера и методами:

```vibe run
struct Stack[T] {
    items: [4]T
    n: i64
}

impl Stack[T] {
    fn push(self, v: T) {
        self.items[self.n] = v
        self.n += 1
    }

    fn top(self) T {
        return self.items[self.n - 1]
    }
}

fn main() {
    var s = Stack[i64]{ .. }
    s.push(3)
    s.push(4)
    println(s.top(), s.n)
}
```

Ограничения параметров записываются так же, как у функций: `struct Sorted[T: Ord] { ... }`. Нарушение ловится при создании типа.

## Что дальше

- Как хранить такие значения в куче: [память и аллокаторы](memory.md), [коллекции](collections.md).
- Как возвращать «значение или ошибку»: [ошибки и опциональные значения](errors-and-optionals.md).
