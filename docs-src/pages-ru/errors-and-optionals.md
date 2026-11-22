---
title: Ошибки и опциональные значения
order: 17
section: Язык
description: Тип !T, error.Имя, ?, catch, errdefer, тип ?T и orelse в Zark с разбором типичных шаблонов
---

В Zark нет исключений. Ошибка — обычное значение, которое функция возвращает рядом с результатом. Всё видно в сигнатуре и в месте вызова.

Для двух разных ситуаций есть два типа:

| Тип | Смысл | Когда использовать |
|---|---|---|
| `!T` | значение `T` **или ошибка** с именем | операция могла сломаться: файл, разбор, нехватка памяти |
| `?T` | значение `T` **или ничего** | отсутствие — нормальный исход: поиск, необязательное поле |

## Ошибки: `!T`

Функция объявляет, что может завершиться ошибкой, добавив `!` перед типом результата. Вернуть ошибку — `return error.Имя`.

```zark run
!i64 safe_div(i64 a, i64 b) {
    if (b == 0) { return error.DivByZero; }
    return a / b;
}

void main() {
    println(safe_div(10, 2) catch -1);
    println(safe_div(1, 0) catch -1);
}
```

Имя ошибки придумывается на месте: `error.DivByZero`, `error.NotFound`. Объявлять списки ошибок заранее не нужно. Одинаковые имена в разных функциях означают одну и ту же ошибку.

Обычное значение `T` подходит там, где ожидается `!T` (это неявное преобразование), поэтому в успешном случае пишите просто `return значение`.

Если результат не нужен, а ошибка возможна, пишите `!void`:

```zark run
!void check(i64 n) {
    if (n < 0) { return error.Negative; }
}

void main() {
    check(5) catch println("плохо");
    check(-5) catch println("плохо");
}
```

Значение `!T` можно положить в переменную и напечатать. Оно печатается как значение или как `error.Имя`:

```zark run
!i64 f(i64 n) {
    if (n == 0) { return error.Zero; }
    return n;
}

void main() {
    const auto a = f(0);
    const auto b = f(2);
    println(a, b);
}
```

Использовать такое значение как обычное число нельзя, оно должно быть сначала «распаковано»:

```zark error
!i64 f() { return 1; }

void main() {
    const i64 x = f();
}
```

## Нельзя игнорировать ошибку

Если вызвать функцию с `!T` и ничего не сделать с результатом, это ошибка компиляции. Забыть про отказ нельзя:

```zark error
!i64 f() { return 1; }

void main() {
    f();
    println("дальше");
}
```

Выберите: пробросить (`?`), обработать (`catch`) или сознательно отбросить (`_ =`).

## Проброс: `?`

`выражение?` — если внутри ошибка, функция **немедленно возвращает её же** вызывающему (выполнив `defer` и `errdefer`). Если значение — оно извлекается.

```zark run
!i64 parse(str s) {
    if (s.len == 0) { return error.Empty; }
    return parse_int(s);
}

!i64 sum(str a, str b) {
    const auto x = parse(a)?;
    const auto y = parse(b)?;
    return x + y;
}

void main() {
    println(sum("10", "32") catch -1);
    println(sum("10", "") catch -1);
    println(sum("10", "x") catch -1);
}
```

`?` можно ставить только в функции, которая сама возвращает `!T`. Иначе непонятно, куда пробрасывать:

```zark error
!i64 f() { return 1; }
i64 g() { return f()?; }

void main() {
    println(g());
}
```

Цепочки `a()?.b()?` читаются слева направо: каждый `?` — точка возможного выхода.

### `main` с `!void`

Если `main` возвращает `!void`, непойманная ошибка завершает программу кодом 1 и печатает `error: Имя`:

```zark run exit
!void load() {
    return error.FileMissing;
}

!void main() {
    println("старт");
    load()?;
    println("сюда не дойдём");
}
```

## Обработка: `catch`

`выражение catch запасное` — результат успешного выражения, а при ошибке — `запасное`.

```zark run
!i64 f(i64 n) {
    if (n == 0) { return error.Zero; }
    return n * 10;
}

void main() {
    println(f(3) catch 0, f(0) catch 0);
    println(parse_int("12") catch -1, parse_int("12x") catch -1);
}
```

### С именем ошибки

`catch |e| { ... }` даёт доступ к ошибке. Блок должен **дать значение** (последнее выражение блока) или **выйти** из функции/цикла через `return`, `break`, `continue`, `panic`.

```zark run
!i64 f(i64 n) {
    if (n == 0) { return error.Zero; }
    if (n < 0) { return error.Negative; }
    return n;
}

void main() {
    const auto r = f(-1) catch |e| {
        println("ошибка: {e}");
        -1;
    };
    println(r);
}
```

Выбрать значение по виду ошибки можно через сравнение. `if` — оператор, поэтому значение заводится заранее:

```zark run
!i64 f(i64 n) {
    if (n == 0) { return error.Zero; }
    return error.Other;
}

void main() {
    const auto r = f(0) catch |e| {
        auto v = 200;
        if (e == error.Zero) { v = 100 };
        v;
    };
    println(r);

    const auto r2 = f(1) catch |e| {
        const auto m = match e {
            error.Zero => 1,
            _ => 2,
        };
        m;
    };
    println(r2);
}
```

Блок, который не даёт значения, — ошибка. Последним должно стоять выражение:

```zark error
!i64 f() { return error.X; }

void main() {
    const auto v = f() catch |e| {
        println(e);
    }
}
```

### Выход вместо значения

В ветке `catch` можно выйти из текущей функции или цикла:

```zark run
!i64 f(i64 n) {
    if (n == 0) { return error.Zero; }
    return n;
}

i64 twice(i64 n) {
    const auto v = f(n) catch return -1;
    return v * 2;
}

void main() {
    println(twice(0), twice(4));
    for (auto i : 0..3) {
        const auto v = f(i) catch continue;
        println("v = {v}");
    }
}
```

### `catch` для `!void`

Если выражение ничего не возвращает, после `catch` стоит просто действие:

```zark run
!void f() { return error.Boom; }

void main() {
    f() catch println("обработано");
    f() catch |e| println("поймано {e}");
    println("конец");
}
```

### Сознательно отбросить: `_ =`

```zark run
!i64 risky() { return error.Fail; }

void main() {
    _ = risky();
    println("ошибка проигнорирована явно");
}
```

Это допустимо, но на практике редко нужно: чаще пишут `catch 0` или `catch return`.

## `errdefer`: откат только при ошибке

`errdefer` выполняется только тогда, когда функция выходит **с ошибкой**. Он нужен для отката частично созданного состояния. Обычный `defer` выполняется всегда (см. [управление потоком](control-flow.md#defer-и-errdefer)).

```zark run
!i64 make(i64 n) {
    errdefer println("откат: make({n}) не удался");
    defer println("в любом случае: закончили make({n})");
    if (n < 0) { return error.Negative; }
    return n * 2;
}

void main() {
    println(make(5) catch 0);
    println(make(-1) catch 0);
}
```

Правило работает и для ошибки, пришедшей через `?`, и для `return g()`, который оказался ошибкой:

```zark run
!void inner() { return error.OutOfRange; }

!void outer() {
    errdefer println("outer: откат");
    inner()?;
    println("не печатается");
}

void main() {
    outer() catch |e| println("main поймал {e}");
}
```

Типичное применение: выделили две вещи, на второй сломались — освободили первую.

## Ошибки в стандартной библиотеке

Функции стандартной библиотеки возвращают ошибки с понятными именами:

| Функция | Ошибки |
|---|---|
| `parse_int(s)` | `error.InvalidNumber` |
| `List.pop()`, `List.last()` | `error.Empty` |
| `Map.get(k)` | `error.NotFound` |
| `read_line(buf)` | `error.EndOfFile` |
| `bprint(buf, ...)`, `to_cstr` | `error.NoSpace` |
| `read_file(a, path)` | `error.FileNotFound`, `error.ReadFailed` |
| `write_file(path, data)` | `error.CannotOpen`, `error.WriteFailed` |
| `env(name)` | `error.NotFound` |
| `run(a, argv)` | `error.Signaled` и ошибки запуска процесса |
| `a.alloc(n)`, `List.push(v)` | `error.OutOfMemory` |

Полная таблица — в [справочнике](stdlib.md).

```zark run
void main() {
    println(parse_int("42") catch -1);
    const auto e = parse_int("abc") catch |e| {
        println("не число: {e}");
        0;
    };
    println(e);
}
```

## Опциональные значения: `?T`

`?T` — «либо значение, либо ничего». Тип `?T` — то же самое, что `Option<T>` из стандартной библиотеки (union с вариантами `Some` и `None`).

В `?T` неявно превращаются значение `T` и `null`:

```zark run
?i64 find(i64[] xs, i64 want) {
    for (auto [i, x] : xs) {
        if (x == want) { return i; }
    }
    return null;
}

void main() {
    const auto xs = [5, 8, 13];
    const auto a = find(xs[..], 13);
    const auto b = find(xs[..], 99);
    println(a, b);
}
```

### `orelse`: запасное значение

`a orelse b` — значение `a`, а если оно пустое, то `b`. Правая часть может быть выходом: `return`, `break`, `continue`.

```zark run
?i64 find(i64[] xs, i64 want) {
    for (auto [i, x] : xs) {
        if (x == want) { return i; }
    }
    return null;
}

i64 index_or_bust(i64[] xs, i64 v) {
    const auto i = find(xs, v) orelse return -7;
    return i * 10;
}

void main() {
    const auto xs = [5, 8, 13];
    println(find(xs[..], 8) orelse -1);
    println(find(xs[..], 99) orelse -1);
    println(index_or_bust(xs[..], 13), index_or_bust(xs[..], 0));
    for (auto i : 0..3) {
        const auto v = find(xs[..], i * 4 + 5) orelse continue;
        println("нашли на {v}");
    }
}
```

> **Ловушка.** Запасное значение того же типа, что и внутри: `?i64 orelse "a"` — ошибка типов.

### Проверка и разбор

```zark run
?i64 pick(i64 n) {
    if (n > 0) { return n; }
    return null;
}

void main() {
    const auto a = pick(5);
    const auto b = pick(-5);
    println(a.is_some(), b.is_some(), b.unwrap_or(9));
    println(a is .Some, b is .None);
    match a {
        .Some(v) => println("значение {v}");
        .None => println("пусто");
    }
    const ?i64 c = .Some(5);
    const ?i64 d = .None;
    println(c, d);
}
```

Методы: `is_some()` и `unwrap_or(запасное)`. Образцы `.Some(v)` и `.None` работают в [`match`](control-flow.md#match-как-выражение), а `is` проверяет вариант.

### Указатель или `?T*`

Для «указатель, который может отсутствовать» используйте `?T*`. Сравнивать значение типа `?T` с `null` напрямую (`x == null`) нельзя: используйте `orelse`, `is .None` или `match`.

```zark run
struct Node { i64 v; }

?Node* find(Node[] xs, i64 v) {
    for (auto i : 0..xs.len) {
        if (xs[i].v == v) { return &xs[i]; }
    }
    return null;
}

void main() {
    auto xs = [Node{ .v = 1 }, Node{ .v = 2 }];
    const auto p = find(xs[..], 2) orelse return;
    p.v = 20;
    println(xs[1].v);
    println(find(xs[..], 5) is .None);
}
```

А обычный указатель `T*` сам может быть `null` и сравнивается с `null` напрямую.

## Вложенность: `!?T`

Операция, которая может сломаться и ещё вернуть «ничего»: `!?T`. Сначала разворачивается `!`, потом `?`:

```zark run
!?i64 lookup(str key) {
    if (key.len == 0) { return error.EmptyKey; }
    if (key == "a") { return 1; }
    return null;
}

void main() {
    const auto a = lookup("a") catch return;
    const auto b = lookup("zz") catch return;
    println(a orelse -1, b orelse -1);
}
```

## Выбор между `!T` и `?T`

Спросите: «если результата нет, это нормально или это поломка?»

- Поиск в списке не нашёл элемент — это нормально → `?T`.
- Файл не открылся, число не разобралось, память кончилась — поломка → `!T`.
- Если важна **причина** — нужен `!T` с говорящим именем ошибки.

## `panic` и `assert`

Для ошибок программиста (нарушенный инвариант) есть `panic("сообщение")` и `assert(условие)`: они печатают место и завершают программу с кодом 1. Они не заменяют `!T`.

```zark run panic
void main() {
    const auto n = 3;
    assert(n > 0);
    println("первое assert прошло");
    assert(n > 5);
    println("не печатается");
}
```

## Что дальше

- Как освобождать ресурсы при любом выходе: [управление потоком](control-flow.md#defer-и-errdefer).
- Ошибки нехватки памяти: [память и аллокаторы](memory.md).
- Проверка ошибок в тестах: [тестирование](testing.md).
