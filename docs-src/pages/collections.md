---
title: Коллекции: List, Map, Option
order: 21
section: Память и данные
description: Динамический массив List[T], хеш-таблица Map[V], Option[T], сортировка и вспомогательные функции стандартной библиотеки Vibe
---

Контейнеры в Vibe — обычные дженерик-структуры, написанные на самом Vibe (исходник — `src/std.vibe`, он подключается автоматически). Магии в них нет, и они подчиняются главному правилу: **память берут только через явный аллокатор**.

Какой контейнер выбрать:

| Нужно | Берите |
|---|---|
| набор элементов известного размера | массив `[N]T` на стеке |
| набор элементов, размер которого растёт | `List[T]` |
| поиск значения по строковому ключу | `Map[V]` |
| «значение или ничего» | `?T` / `Option[T]` |

## `List[T]` — динамический массив

```vibe run
fn main() !void {
    var xs = List[i64].init(c_allocator())
    defer xs.deinit()

    xs.push(5)?
    xs.push(1)?
    xs.push(3)?
    println(xs.slice(), xs.len)
}
```

Три правила:

1. `List[T].init(a)` запоминает аллокатор. До `init` у списка аллокатора нет, и `push` в «нулевой» список работать не будет.
2. Любое **растущее** действие возвращает `!void`: память может кончиться. Пишите `?` или `catch`.
3. В конце вызовите `deinit()`. Для арены он не нужен (см. [память](memory.md#arena-выделять-много-освободить-разом)).

### Структура списка

```vibe
struct List[T] {
    items: []T   // выделенный буфер, items.len — ёмкость
    len: i64     // сколько элементов реально лежит
    a: Allocator
}
```

Поэтому `xs.len` — число элементов, а `xs.items.len` — ёмкость. Буфер растёт по удвоению: 8, 16, 32 и так далее.

### Методы

| Метод | Что делает |
|---|---|
| `init(a)` | создаёт пустой список |
| `deinit()` | освобождает буфер |
| `push(v) !void` | добавляет в конец |
| `append(slice) !void` | добавляет несколько |
| `pop() !T` | убирает и возвращает последний; `error.Empty` на пустом |
| `last() !T` | последний, не убирая; `error.Empty` на пустом |
| `get(i) T` | элемент (с проверкой границ) |
| `set(i, v)` | записывает элемент |
| `slice() []T` | текущие элементы как срез |
| `is_empty() bool` | пуст ли |
| `clear()` | обнуляет длину, память остаётся |
| `contains(v) bool` | есть ли такой элемент (нужен `==`) |
| `reverse()` | переворачивает на месте |
| `sort()` | сортирует на месте (нужны `<`, `>`) |
| `reserve(n) !void` | заранее выделяет ёмкость |

```vibe run
fn main() !void {
    var xs = List[i64].init(c_allocator())
    defer xs.deinit()

    xs.push(5)?
    xs.push(1)?
    xs.push(3)?
    xs.append([9, 7])?
    println(xs.slice(), xs.len, xs.is_empty())
    println(xs.contains(3), xs.contains(4))

    println(xs.get(1), xs.last()?, xs.pop()?)
    xs.set(0, 50)
    xs.sort()
    println(xs.slice())
    xs.reverse()
    println(xs.slice())

    xs.reserve(100)?
    println(xs.len, xs.items.len)
    xs.clear()
    println(xs.len, xs.pop() catch -1)
}
```

### Перебор

`for` умеет перебирать всё, у чего есть `slice()`, поэтому список идёт прямо в цикл:

```vibe run
fn main() !void {
    var xs = List[i64].init(c_allocator())
    defer xs.deinit()
    for i in 1..5 { xs.push(i * 10)? }

    for x in xs { println(x) }
    for i, x in xs { println("{i}: {x}") }

    var total = 0
    for x in xs.slice() { total += x }
    println(total)
}
```

### Изменение элементов на месте

`get` возвращает **копию**. Чтобы менять элементы структур, берите указатель на элемент:

```vibe run
struct Player { name: str, score: i64 }

fn main() !void {
    var ps = List[Player].init(c_allocator())
    defer ps.deinit()
    ps.push(Player{ name: "ann", score: 1 })?
    ps.push(Player{ name: "bob", score: 2 })?

    var copy = ps.get(0)
    copy.score = 100
    println(ps.get(0).score)

    let p = &ps.items[0]
    p.score = 99
    println(ps.get(0).score)

    for i in 0..ps.len { ps.items[i].score += 1 }
    for p in ps { println(p.name, p.score) }
}
```

> **Ловушка.** Указатель на элемент (`&ps.items[0]`) недействителен после `push`: список мог перенести буфер в другое место. Не держите такие указатели, если будете добавлять элементы.

### Стек, очередь, срезы

Стек — это `push` + `pop`:

```vibe run
fn main() !void {
    var st = List[i64].init(c_allocator())
    defer st.deinit()
    st.push(1)?
    st.push(2)?
    st.push(3)?
    while !st.is_empty() {
        println(st.pop()?)
    }
}
```

Срез от списка (`xs.slice()`) тоже можно резать (`xs.slice()[1..3]`), но он «следит» за теми же данными и устаревает вместе с буфером.

### Список в списке

```vibe run
fn main() !void {
    var arena = Arena.init(c_allocator())
    defer arena.deinit()
    let a = arena.allocator()

    var rows = List[List[i64]].init(a)
    for r in 0..3 {
        var row = List[i64].init(a)
        for c in 0..3 { row.push(r * 3 + c)? }
        rows.push(row)?
    }
    for r in rows { println(r.slice()) }
}
```

Здесь арена освобождает всё сразу, поэтому `deinit` у вложенных списков не нужен.

## `Map[V]` — хеш-таблица со строковыми ключами

Ключ — всегда `str`, значение — любой тип `V`.

```vibe run
fn main() !void {
    var m = Map[i64].init(c_allocator())
    defer m.deinit()

    m.put("one", 1)?
    m.put("two", 2)?
    m.put("one", 11)?

    println(m.get("one")?)
    println(m.get("zzz") catch -1)
    println(m.has("two"), m.has("x"), m.len)
}
```

| Метод | Что делает |
|---|---|
| `init(a)` | пустая таблица |
| `deinit()` | освобождает память |
| `put(key, value) !void` | добавляет или заменяет |
| `get(key) !V` | значение или `error.NotFound` |
| `has(key) bool` | есть ли ключ |
| `len` | число ключей |

> **Ловушка.** Ключи **не копируются**: таблица хранит срез, который вы дали. Если ключ собирается из временного буфера, скопируйте его через `a.dup(key)`, иначе он испортится, когда буфер перезапишут.

Удалять ключи нельзя (метода `remove` нет). `get` возвращает копию значения: чтобы изменить значение на месте, нужно работать с `m.entries`.

### Перебор

Специального итератора нет, но таблица — это массив записей `entries`, и занятые записи помечены `used`:

```vibe run
fn main() !void {
    var m = Map[i64].init(c_allocator())
    defer m.deinit()
    m.put("a", 1)?
    m.put("b", 2)?
    m.put("c", 3)?

    var total = 0
    for e in m.entries {
        if e.used {
            total += e.value
        }
    }
    println(total, m.len)

    for e in m.entries {
        if e.used && e.key == "b" { println("нашли {e.key} = {e.value}") }
    }
}
```

Порядок обхода — порядок слотов хеш-таблицы, а не порядок вставки. Не рассчитывайте на него.

### Счётчик слов

Типичная задача: посчитать, сколько раз встретилось каждое слово.

```vibe run
fn main() !void {
    var arena = Arena.init(c_allocator())
    defer arena.deinit()
    let a = arena.allocator()

    let text = "to be or not to be"
    var counts = Map[i64].init(a)
    var start = 0
    for i in 0..text.len + 1 {
        if i == text.len || text[i] == ' ' {
            let w = text[start..i]
            let n = counts.get(w) catch 0
            counts.put(w, n + 1)?
            start = i + 1
        }
    }
    println(counts.get("to")?, counts.get("be")?, counts.get("or")?, counts.len)
}
```

Ключи здесь — срезы `text`, а `text` — литерал, который живёт всё время работы, поэтому копировать ключи не нужно.

### Значения-структуры

```vibe run
struct Stat { count: i64, sum: i64 }

fn main() !void {
    var m = Map[Stat].init(c_allocator())
    defer m.deinit()
    m.put("a", Stat{ count: 1, sum: 10 })?
    let s = m.get("a")?
    println(s.count, s.sum)
}
```

## `Option[T]` и `?T`

`?T` — запись для `Option[T]`: union с вариантами `Some: T` и `None`. Подробно — в [ошибках и опциональных значениях](errors-and-optionals.md#опциональные-значения-t).

```vibe run
fn main() {
    let a: ?i64 = .Some(5)
    let b: ?i64 = .None
    println(a.is_some(), b.is_some(), b.unwrap_or(9))
    println(a orelse 0, b orelse 0)
}
```

## Сортировка и вспомогательные функции

| Функция | Что делает |
|---|---|
| `sort(slice)` | быстрая сортировка на месте; нужны `<` и `>` у элементов |
| `min(a, b)`, `max(a, b)` | меньшее и большее |
| `abs(x)` | модуль числа |
| `swap(&a, &b)` | меняет два значения местами |

```vibe run
fn main() {
    var xs = [5, 2, 9, 1]
    sort(xs[..])
    println(xs)
    var fs = [3.5, 1.5, 2.5]
    sort(fs[..])
    println(fs)
    println(min(3, 4), max(3.5, 1.0), abs(-5), abs(-2.5))
    var a = 1
    var b = 2
    swap(&a, &b)
    println(a, b)
}
```

Сортировать строки или структуры `sort` не умеет (у них нет `<`). Для них напишите свой цикл со своей функцией сравнения.

### Сортировка по ключу

```vibe run
struct P { name: str, age: i64 }

fn sort_by_age(ps: []P) {
    for i in 1..ps.len {
        var j = i
        while j > 0 && ps[j - 1].age > ps[j].age {
            swap(&ps[j - 1], &ps[j])
            j -= 1
        }
    }
}

fn main() {
    var ps = [P{ name: "a", age: 30 }, P{ name: "b", age: 20 }, P{ name: "c", age: 25 }]
    sort_by_age(ps[..])
    for p in ps { println(p.name, p.age) }
}
```

## Массивы и срезы

Если размер заранее известен, список не нужен. Массив на стеке быстрее, ничего не выделяет и не требует `deinit`:

```vibe run
fn main() {
    var grid: [3][3]i64
    for r in 0..3 {
        for c in 0..3 {
            grid[r][c] = r * 3 + c
        }
    }
    println(grid)
    println(grid[1][2], grid.len, grid[0].len)
}
```

Функции принимают **срез**, поэтому одна и та же функция работает и с массивом, и со списком (`xs.slice()`):

```vibe run
fn total(xs: []i64) i64 {
    var t = 0
    for x in xs { t += x }
    return t
}

fn main() !void {
    let arr = [1, 2, 3]
    var list = List[i64].init(c_allocator())
    defer list.deinit()
    list.append([10, 20])?
    println(total(arr[..]), total(list.slice()))
}
```

## Что дальше

- Сами аллокаторы: [память и аллокаторы](memory.md).
- Справочник по всем функциям: [стандартная библиотека](stdlib.md).
