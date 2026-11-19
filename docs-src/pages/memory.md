---
title: Память и аллокаторы
order: 20
section: Память и данные
description: Стек и куча, явный Allocator, c_allocator, FixedBuf, Arena, create/destroy, свой аллокатор и типичные ошибки работы с памятью в Vibe
---

Главное правило языка: **ничто не выделяет память само.** Ни строки, ни интерполяция, ни замыкания, ни `println`. Куча появляется только там, где вы явно передали **аллокатор**. Поэтому, читая код, вы всегда видите, кто, где и сколько берёт.

## Стек и куча

Обычные переменные, массивы и структуры живут на **стеке** функции и исчезают при выходе из неё. Для данных, которые нужно сохранить дольше или размер которых неизвестен заранее, нужна **куча**, а к ней доступ через аллокатор.

```vibe run
fn main() {
    var local: [4]i64
    local[0] = 1
    println(local, sizeof([256]u8))
}
```

Массив фиксированного размера на стеке — самый дешёвый способ получить память. Но размер должен быть известен при компиляции, а вернуть такой массив срезом из функции нельзя: после возврата стек освободится.

## Allocator

`Allocator` — маленькая структура из трёх полей: контекст и две функции.

```vibe
struct Allocator {
    ctx: *void
    alloc_fn: fn(*void, u64, u64) *void
    free_fn: fn(*void, *void, u64)
}
```

Любой аллокатор — это такие три значения. Готовые аллокаторы из стандартной библиотеки:

| Аллокатор | Откуда берёт память | Освобождение |
|---|---|---|
| `c_allocator()` | `calloc` / `free` из libc | каждый кусок отдельно |
| `FixedBuf.init(buf)` | ваш готовый буфер, кучи нет | `reset()` для всего сразу |
| `Arena.init(parent)` | кусками у родительского аллокатора | `deinit()` для всего сразу |

И методы любого аллокатора `a`:

| Метод | Что делает |
|---|---|
| `a.alloc[T](n) ![]T` | `n` элементов, заполненных **нулями** |
| `a.free(slice)` | освобождает срез, полученный из `alloc` |
| `a.create[T]() !*T` | один `T` в куче, нули |
| `a.destroy(p)` | освобождает `create` |
| `a.dup(s) !str` | копия строки |
| `a.dupz(s) !*u8` | копия с нулевым байтом в конце, для C |

Каждая операция выделения возвращает `!...`: когда память кончилась, вы получаете обычную ошибку `error.OutOfMemory`, а не падение.

### `alloc` и `free`

```vibe run
fn main() !void {
    let a = c_allocator()
    let xs = a.alloc[i64](4)?
    defer a.free(xs)
    println(xs, xs.len)
    xs[0] = 10
    xs[3] = 40
    println(xs)
}
```

Память нулевая: можно читать без инициализации. Размер среза можно узнать как `xs.len`.

> **Совет.** Сразу после получения памяти пишите `defer a.free(...)`. Тогда она освободится на любом выходе из функции, даже по ошибке.

### `create` и `destroy`

Для одного объекта, например узла списка:

```vibe run
struct Node {
    val: i64
    next: *Node
}

fn main() !void {
    let a = c_allocator()
    let n1 = a.create[Node]()?
    defer a.destroy(n1)
    let n2 = a.create[Node]()?
    defer a.destroy(n2)
    n1.val = 1
    n1.next = n2
    n2.val = 2
    println(n1.val, n1.next.val, n2.next == null)
}
```

### `dup`

```vibe run
fn main() !void {
    let a = c_allocator()
    var src: [3]u8 = [104, 105, 33]
    let copy = a.dup(src[..])?
    defer a.free(copy)
    src[0] = 72
    println(copy, src[..])
}
```

## Ошибка нехватки памяти

В Vibe нехватка памяти — не катастрофа, а значение, которое обрабатывается. Это особенно важно для `FixedBuf`, у которого память ограничена:

```vibe run
fn main() {
    var mem: [64]u8
    var fb = FixedBuf.init(mem[..])
    let a = fb.allocator()
    println(fb.remaining())
    let first = a.alloc[u8](40) catch return
    println(first.len, fb.remaining())
    let second = a.alloc[u8](40) catch |e| {
        println("не хватило: {e}")
        return
    }
    println(second.len)
}
```

## `FixedBuf`: без кучи вообще

`FixedBuf` раздаёт память из вашего массива «по возрастающей». Отдельные куски освобождать не нужно: `free` возвращает память, только если это самое последнее выделение, иначе ничего не делает. Весь буфер возвращается одним вызовом `reset()`. Аллокатор хранит указатель на `fb`, поэтому переменная `fb` должна жить, пока вы пользуетесь аллокатором.

```vibe run
fn main() !void {
    var mem: [256]u8
    var fb = FixedBuf.init(mem[..])
    let a = fb.allocator()

    var list = List[i64].init(a)
    for i in 0..5 { list.push(i * i)? }
    println(list.slice(), fb.remaining())

    fb.reset()
    println(fb.remaining())
}
```

Применения: встроенные системы, обработка запроса «в рамках бюджета», функции, которые не должны трогать кучу. Весь код на `FixedBuf` работает без единого `malloc`.

> **Ловушка.** После `fb.reset()` все ранее выданные куски недействительны (на них нет защиты). Не используйте старые срезы и контейнеры после сброса: `list` выше нужно заново инициализировать.

## `Arena`: выделять много, освободить разом

`Arena` берёт крупные куски у родительского аллокатора и раздаёт из них маленькие. Куски берутся порциями от 64 КБ. Отдельные `free` ничего не делают, а `deinit()` освобождает **всё** сразу. Идеальна для данных с общим временем жизни: разбор файла, обработка одного запроса, построение дерева.

```vibe run
fn main() !void {
    var arena = Arena.init(c_allocator())
    defer arena.deinit()
    let a = arena.allocator()

    var words = List[str].init(a)
    let w1 = a.dup("alpha")?
    let w2 = a.dup("beta")?
    words.push(w1)?
    words.push(w2)?
    println(words.slice())

    for i in 0..1000 {
        _ = a.alloc[i64](100)?
    }
    println("тысяча массивов выделена и ни одного free")
}
```

Не нужно вызывать `list.deinit()` или `a.free(w1)`: всё уйдёт вместе с `arena.deinit()`. Именно так устроен сам компилятор Vibe: одна арена на запуск.

Типичный шаблон: аллокатор передаётся параметром.

```vibe run
struct Config {
    name: str
    values: List[i64]
}

fn load(a: Allocator) !Config {
    var cfg = Config{ name: a.dup("config")?, values: List[i64].init(a) }
    for i in 1..4 { cfg.values.push(i * 10)? }
    return cfg
}

fn main() !void {
    var arena = Arena.init(c_allocator())
    defer arena.deinit()
    let cfg = load(arena.allocator())?
    println(cfg.name, cfg.values.slice())
}
```

Функция `load` не знает, какой аллокатор ей дали. Вызывающий решает: арена, `FixedBuf` или `c_allocator`.

## Свой аллокатор

Достаточно заполнить три поля. Например, счётчик, который считает выделения и передаёт работу родителю:

```vibe run
struct Counting {
    count: i64
    bytes: i64
    parent: Allocator
}

fn count_alloc(ctx: *void, size: u64, align: u64) *void {
    let c = ctx as *Counting
    c.count += 1
    c.bytes += size as i64
    return c.parent.alloc_fn(c.parent.ctx, size, align)
}

fn count_free(ctx: *void, p: *void, size: u64) {
    let c = ctx as *Counting
    c.parent.free_fn(c.parent.ctx, p, size)
}

fn main() !void {
    var stats = Counting{ count: 0, bytes: 0, parent: c_allocator() }
    let a = Allocator{ ctx: &stats as *void, alloc_fn: count_alloc, free_fn: count_free }

    var list = List[i64].init(a)
    defer list.deinit()
    for i in 0..20 { list.push(i)? }
    println(list.len, stats.count, stats.bytes)
}
```

`alloc_fn(ctx, size, align)` обязана вернуть **нулевую** память или `null`, когда не хватило. `free_fn(ctx, ptr, size)` получает указатель и тот же размер.

20 элементов потребовали три выделения (8, 16 и 32 элемента по 8 байт: 64 + 128 + 256 = 448 байт): список удваивает ёмкость.

## Стековые данные и указатели

Указатель на локальную переменную нельзя возвращать:

```vibe
fn bad() *i64 {
    var x = 5
    return &x
}
```

Такой код компилируется, но после выхода из `bad` стек перезаписывается, и указатель «висит». Компилятор такое **не проверяет**. То же с срезом локального массива и с замыканием (см. [замыкания](functions.md#замыкания)).

Правило: данные, переживающие функцию, должны лежать в памяти, которой владеет вызывающий (параметр-срез, указатель, аллокатор).

```vibe run
fn fill(out: []i64) {
    for i in 0..out.len { out[i] = i * i }
}

fn main() {
    var buf: [5]i64
    fill(buf[..])
    println(buf)
}
```

## Чего не проверяет компилятор

| Проблема | Что будет |
|---|---|
| Использование после `free` | неопределённое поведение |
| Двойной `free` | неопределённое поведение |
| Утечка (забыли `free`/`deinit`) | молча; память освободится при выходе процесса |
| Выход за границы среза или массива | **проверяется**: паника с файлом и строкой |
| Выход за границы через указатель | не проверяется |
| Деление на ноль | аварийное завершение |

Дисциплина проста: пишите `defer` сразу после выделения, передавайте аллокатор вниз, и заводите арену, если не хотите считать отдельные `free`.

## Выбор аллокатора

- Простая программа, которой нужен один-два объекта → `c_allocator()` и `defer`.
- Много мелких выделений с общим временем жизни → `Arena`.
- Нельзя трогать кучу или память ограничена → `FixedBuf`.
- Нужна статистика, отладка, особые правила → свой `Allocator`.

## Что дальше

- Контейнеры, которые принимают аллокатор: [коллекции](collections.md).
- Как работает `defer`: [управление потоком](control-flow.md#defer-и-errdefer).
- Обработка `OutOfMemory`: [ошибки и опциональные значения](errors-and-optionals.md).
