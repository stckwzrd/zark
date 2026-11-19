---
title: Управление потоком
order: 14
section: Язык
description: if, while, for, break, continue, match и defer в Vibe: все формы с примерами и граничными случаями
---

Управляющих конструкций немного, и у каждой одна форма записи. Скобок вокруг условия нет, а фигурные скобки блока обязательны всегда, даже для одного оператора.

## `if` / `else`

```vibe run
fn main() {
    let n = 7
    if n > 10 {
        println("больше десяти")
    } else if n > 5 {
        println("между пятью и десятью")
    } else {
        println("пять или меньше")
    }
}
```

Условие обязано быть `bool`. Число или указатель в роли условия не принимаются, нужно явное сравнение:

```vibe error fragment
let n = 5
if n { println("да") }
```

Фигурные скобки обязательны:

```vibe error fragment
let n = 5
if n > 3 println("да")
```

`if` — это оператор, а не выражение: `let x = if ... ` не пишется. Когда нужно выбрать значение по условию, используйте [`match`](#match-как-выражение) или заранее заведённую `var`:

```vibe run
fn main() {
    let n = 7
    var kind = "мало"
    if n > 5 { kind = "много" }
    println(kind)

    let size = match n > 5 {
        true => "большой",
        false => "маленький",
    }
    println(size)
}
```

## `while`

```vibe run
fn main() {
    var i = 0
    while i < 3 {
        println("i = {i}")
        i += 1
    }

    var n = 100
    while n > 1 {
        n /= 3
    }
    println(n)
}
```

Бесконечный цикл пишется как `while true { ... }` и покидается через `break` или `return`.

## `for` по диапазону

`for i in a..b` перебирает целые от `a` включительно до `b` **не включая**. Если `a >= b`, цикл не выполнится ни разу. Конец диапазона вычисляется один раз до начала цикла.

```vibe run
fn main() {
    for i in 0..4 {
        println(i)
    }
    for i in 5..5 { println("не печатается") }
    for i in 3..0 { println("тоже не печатается") }
    let n = 3
    var sum = 0
    for i in 1..n + 1 { sum += i }
    println(sum)
}
```

Включающей формы `0..=3` нет: пишите `0..4`. Обратного хода тоже нет. Для обратного прохода используйте `while`:

```vibe run
fn main() {
    var i = 3
    while i > 0 {
        i -= 1
        println(i)
    }
}
```

Диапазон существует только внутри `for`: сохранить `0..3` в переменную нельзя.

Переменная цикла неизменяема внутри тела:

```vibe error fragment
for i in 0..3 {
    i += 1
}
```

## `for` по коллекции

`for x in seq` перебирает элементы массива, среза или любого значения с методом `slice()` (например, `List`). `for i, x in seq` добавляет индекс.

```vibe run
fn main() {
    let arr = [10, 20, 30]
    for x in arr { println(x) }
    for i, x in arr { println("{i}: {x}") }
    for c in "abc" { println(c) }

    var list = List[i64].init(c_allocator())
    defer list.deinit()
    list.push(7) catch return
    list.push(8) catch return
    for i, v in list { println(i, v) }
}
```

Строка перебирается побайтово: `c` здесь число типа `u8` (97, 98, 99). Элемент — это **копия**. Чтобы изменить элементы на месте, идите по индексу:

```vibe run
fn main() {
    var xs = [1, 2, 3]
    for i in 0..xs.len {
        xs[i] *= 10
    }
    println(xs)
}
```

Перебирать число нельзя:

```vibe error fragment
for x in 5 { println(x) }
```

## `break` и `continue`

`break` выходит из ближайшего цикла, `continue` переходит к следующей итерации. Меток для выхода из нескольких вложенных циклов нет: выносите внутренний цикл в функцию и используйте `return`.

```vibe run
fn main() {
    var i = 0
    while true {
        i += 1
        if i == 2 { continue }
        if i > 4 { break }
        println("i = {i}")
    }

    for a in 0..3 {
        for b in 0..3 {
            if b == 1 { break }
            println("a={a} b={b}")
        }
    }
}
```

`break` и `continue` работают и внутри `match`, влияя на объемлющий цикл:

```vibe run
fn main() {
    for x in [1, 2, 3, 4, 5] {
        match x {
            2 => continue
            4 => break
            _ => {}
        }
        println(x)
    }
}
```

## `match`

`match` сравнивает значение с образцами сверху вниз и выполняет первую подходящую ветку. «Проваливания» между ветками нет.

```vibe run
enum Dir { North, East, South, West }

fn main() {
    let d: Dir = .East
    match d {
        .North => println("вверх")
        .East, .West => println("вбок")
        _ => println("вниз")
    }

    let n = 3
    match n {
        1, 2 => println("мало")
        3 => {
            println("три")
        }
        _ => {}
    }

    let cmd = "stop"
    match cmd {
        "go" => println("едем")
        "stop" => println("стоим")
        _ => println("непонятно")
    }
}
```

Что можно разбирать: целые числа, символы (`'a'`), enum, строки (через `==`) и union. Образец может быть литералом или константой, несколько образцов в одной ветке разделяются запятой. Диапазонов (`1..5`) в образцах нет.

Ветка `_` — «всё остальное». В **операторе** `match` она необязательна: если ничего не подошло, ничего не произойдёт.

```vibe run
fn main() {
    let n = 5
    match n {
        1 => println("a")
    }
    println("после match")
}
```

### Union и привязка payload

Для union образец `.Вариант(имя)` привязывает содержимое варианта к имени. Привязанное значение только для чтения, оно живёт внутри ветки.

```vibe run
union Shape {
    Circle: f64
    Rect: i64
    Empty
}

fn describe(s: Shape) {
    match s {
        .Circle(r) => println("круг r = {r}")
        .Rect(w) => println("квадрат {w}x{w}")
        .Empty => println("пусто")
    }
}

fn main() {
    describe(.Circle(1.5))
    describe(.Rect(4))
    describe(.Empty)
}
```

Если payload не нужен, пишите вариант без скобок: `.Empty` (у варианта без payload) или `.Circle(_)`.

### `match` как выражение

`match` может стоять справа от `=`, в `return`, в аргументе. Ветки тогда — выражения (или блоки, значением которых служит последнее выражение), все приводятся к одному типу.

```vibe run
enum Level { Low, Mid, High }

fn score(l: Level) i64 {
    return match l {
        .Low => 1,
        .Mid => 5,
        .High => 10,
    }
}

fn main() {
    let x = 4
    let word = match x {
        1 => "один",
        2 => "два",
        _ => "много",
    }
    println(word, score(.High))

    let doubled = match x {
        4 => {
            let t = x * 2
            t + 1
        },
        _ => 0,
    }
    println(doubled)
}
```

У `match`-выражения есть жёсткое требование: он должен быть **исчерпывающим**. Покройте все варианты или добавьте `_`:

```vibe error
enum D { N, E }

fn main() {
    let d: D = .E
    let v = match d {
        .N => 1,
    }
    println(v)
}
```

Ветка может не давать значение вовсе, а выходить из функции или цикла через `return`, `break`, `continue`:

```vibe run
fn first_positive(xs: []i64) i64 {
    for x in xs {
        let ok = match x > 0 {
            true => x,
            false => continue,
        }
        return ok
    }
    return -1
}

fn main() {
    println(first_positive([-3, 0, 4, 9]))
    println(first_positive([-1, -2]))
}
```

## `defer` и `errdefer`

`defer оператор` откладывает оператор до выхода из текущего блока: через конец блока, `return`, `break` или `continue`. Несколько `defer` выполняются в обратном порядке, последний объявленный — первым.

```vibe run
fn main() {
    defer println("объявлен первым, выполнится последним")
    defer println("объявлен вторым, выполнится первым")
    println("тело")
}
```

`defer` привязан к **блоку**, а не к функции. В цикле он срабатывает на каждой итерации:

```vibe run
fn main() {
    for i in 0..3 {
        defer println("конец итерации {i}")
        if i == 1 { continue }
        println("тело {i}")
    }
}
```

Откладывать можно и блок:

```vibe run
fn work() i64 {
    var x = 1
    defer {
        println("очистка, x = {x}")
        x = 100
    }
    return x
}

fn main() {
    println(work())
}
```

Значение `return` вычисляется **до** `defer`, поэтому `work()` вернул `1`, хотя `defer` потом записал в `x` число 100.

Типичное применение — освободить ресурс сразу после получения:

```vibe run
fn main() !void {
    var list = List[i64].init(c_allocator())
    defer list.deinit()
    list.push(1)?
    list.push(2)?
    println(list.slice())
}
```

### `errdefer`

`errdefer` — то же самое, но только на путях, где функция вернула **ошибку** (`return error.X`, `?` на ошибке и т. п.). На успешном выходе он не выполняется. Идеален для отката частично созданного:

```vibe run
fn make(n: i64) !i64 {
    errdefer println("откат: make({n}) провалился")
    defer println("в любом случае: завершили make({n})")
    if n < 0 { return error.Negative }
    return n * 2
}

fn main() {
    println(make(5) catch 0)
    println(make(-1) catch 0)
}
```

Подробнее про ошибки: [ошибки и опциональные значения](errors-and-optionals.md).

## Чего нет

- Тернарного оператора `a ? b : c` (используйте `match` или `if`).
- `do { } while`, `loop`, меток `'outer:`.
- `switch` с проваливанием.
- `goto`.
- Диапазонов в `match` и включающих диапазонов `0..=n`.

Всё это сделано сознательно: одна форма на одно действие.

## Что дальше

- Как оформлять код в функции: [функции](functions.md).
- Составные типы и их разбор: [структуры, union и enum](structs-unions-enums.md).
