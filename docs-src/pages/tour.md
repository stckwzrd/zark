---
title: Быстрый тур
order: 2
section: Старт
description: Весь язык Vibe на одной странице: короткие программы с настоящим выводом
---

Эта страница показывает всё основное за один присест. Подробности каждой темы — на отдельных страницах, ссылки в конце разделов.

## Переменные

`let` создаёт неизменяемую привязку, `var` — изменяемую. Тип выводится из значения.

```vibe run fragment
let a = 10
var b = 20
b += a
let pi: f64 = 3.14159
println("a = {a}, b = {b}, pi = {pi}")
```

Попытка изменить `let` не компилируется:

```vibe error fragment
let a = 10
a = 11
```

Подробнее: [переменные и константы](variables.md).

## Числа и преобразования

Целые и дробные типы называются как в Rust: `i8..i64`, `u8..u64`, `f32`, `f64`. Неявно расширять можно только без потерь, остальное — через `as`.

```vibe run fragment
let small: i32 = 1000
let big: i64 = small
let back = big as i32
let f = 7 as f64 / 2.0
let t = 3.99 as i64
println(big, back, f, t)
```

Сужение без `as` не компилируется:

```vibe error fragment
let big: i64 = 1000
let small: i32 = big
```

Подробнее: [типы](types.md), [операторы](operators.md).

## Строки и форматирование

`str` — это срез байтов. Внутри `"..."` в фигурных скобках можно писать любое выражение, после двоеточия — формат.

```vibe run fragment
let name = "Vibe"
let n = 255
println("{name} has {name.len} letters")
println("hex {n:x}, padded {n:08X}, width [{n:6}] [{n:-6}]")
println("pi ~ {3.14159265:.3}")
```

Подробнее: [строки и форматирование](strings.md).

## Управление потоком

```vibe run fragment
for i in 1..6 {
    if i % 2 == 0 {
        println("{i} чётное")
    } else {
        println("{i} нечётное")
    }
}
var n = 3
while n > 0 {
    n -= 1
}
println("n = {n}")
```

Подробнее: [управление потоком](control-flow.md).

## Функции

```vibe run
fn square(x: i64) i64 {
    return x * x
}

fn greet(name: str) {
    println("Привет, {name}!")
}

fn main() {
    greet("Vibe")
    println(square(12))
}
```

Подробнее: [функции](functions.md).

## Структуры и методы

```vibe run
struct Point { x: i64, y: i64 }

impl Point {
    fn new(x: i64, y: i64) Point {
        return Point{ x: x, y: y }
    }

    fn len2(self) i64 {
        return self.x * self.x + self.y * self.y
    }
}

fn main() {
    let p = Point.new(3, 4)
    println("{p.x},{p.y} -> {p.len2()}")
    println(p)
}
```

Подробнее: [структуры, union и enum](structs-unions-enums.md).

## Enum, union и match

```vibe run
enum Color { Red, Green, Blue }

union Shape {
    Circle: f64
    Rect: i64
    Empty
}

fn name(c: Color) str {
    return match c {
        .Red => "красный",
        .Green => "зелёный",
        .Blue => "синий",
    }
}

fn area(s: Shape) f64 {
    return match s {
        .Circle(r) => 3.14 * r * r,
        .Rect(w) => w as f64,
        .Empty => 0.0,
    }
}

fn main() {
    println(name(.Green))
    println(area(.Circle(2.0)), area(.Rect(5)), area(.Empty))
}
```

## Ошибки

Ошибка — значение. Функция, которая может завершиться ошибкой, возвращает `!T`. Оператор `?` пробрасывает ошибку вверх, `catch` — обрабатывает.

```vibe run exit
fn parse(s: str) !i64 {
    if s.len == 0 { return error.Empty }
    return parse_int(s)
}

fn main() !void {
    println(parse("42")?)
    println(parse("") catch -1)
    println(parse("abc") catch |e| { println("ошибка: {e}"); 0 })
    let n = parse("x")?
    println(n)
}
```

Последняя строка завершает программу с ошибкой: `main` вернул `error.InvalidNumber`.

Подробнее: [ошибки и опциональные значения](errors-and-optionals.md).

## Опциональные значения

`?T` — значение или ничего. `orelse` подставляет запасное.

```vibe run
fn find(items: []i64, want: i64) ?i64 {
    for i, x in items {
        if x == want { return i }
    }
    return null
}

fn main() {
    let xs = [5, 8, 13]
    println(find(xs[..], 13) orelse -1)
    println(find(xs[..], 99) orelse -1)
}
```

## Память

Ничто не выделяет память само. Куча — только через аллокатор, который вы передаёте явно.

```vibe run
fn main() !void {
    var arena = Arena.init(c_allocator())
    defer arena.deinit()
    let a = arena.allocator()

    var list = List[i64].init(a)
    for i in 1..6 { list.push(i * i)? }
    println(list.slice())
}
```

`defer` выполняется при выходе из области видимости: `arena.deinit()` освободит всё разом. Подробнее: [память и аллокаторы](memory.md).

## Дженерики

```vibe run
fn largest[T: Ord](a: T, b: T) T {
    if a > b { return a }
    return b
}

struct Pair[A, B] { first: A, second: B }

fn main() {
    println(largest(3, 9), largest(2.5, 1.5))
    let p = Pair[i64, str]{ first: 1, second: "один" }
    println(p.first, p.second)
}
```

## Замыкания

Замыкание явно перечисляет, какие переменные оно использует. Контекст живёт на стеке, ничего не выделяется.

```vibe run
fn apply(f: fn[](i64) i64, x: i64) i64 {
    return f(x)
}

fn main() {
    let k = 10
    var calls = 0
    let add = fn[k, calls](x: i64) i64 {
        calls += 1
        return x + k
    }
    println(apply(add, 1), apply(add, 2), calls)
}
```

## Тесты

```vibe test
fn add(a: i64, b: i64) i64 { return a + b }

test "складывает" {
    assert(add(2, 3) == 5)
}

test "ноль нейтрален" {
    assert(add(7, 0) == 7)
}
```

Подробнее: [тесты](testing.md).

## Модули

Файл подключается через `import`. С `as` его имена получают префикс:

```vibe file=geometry.vibe
struct Rect { w: i64, h: i64 }

fn area(r: Rect) i64 { return r.w * r.h }
```

```vibe run
import "geometry.vibe" as geo

fn main() {
    let r = geo.Rect{ w: 3, h: 4 }
    println(geo.area(r))
}
```

Подробнее: [модули и импорт](modules.md).

## Вызов C

```vibe run
extern fn atoi(s: *u8) i32

fn main() {
    println(atoi("1234") + 1)
}
```

Подробнее: [взаимодействие с C](c-interop.md).

## Куда дальше

- Углубляться в порядке страниц раздела «Язык»: [лексика](lexical.md), [типы](types.md) и далее.
- Посмотреть готовые программы: [рецепты](cookbook.md).
- Если что-то ведёт себя неожиданно: [ловушки и FAQ](gotchas.md).
