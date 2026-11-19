---
title: Шпаргалка
order: 44
section: Справочник
description: Весь синтаксис Vibe на одной странице: таблицы и короткие примеры для быстрого поиска
---

Краткая памятка. Подробности по каждой теме — по ссылкам.

## Программа

```vibe run
fn main() {
    println("Привет, Vibe!")
}
```

| Команда | Что делает |
|---|---|
| `vibe run f.vibe [-- args]` | собрать и запустить |
| `vibe build f.vibe [-o out] [--release]` | собрать исполняемый файл |
| `vibe test f.vibe` | запустить блоки `test` |
| `vibe fmt [--check] f.vibe` | отформатировать |
| `vibe lsp` | языковой сервер |
| `vibe ir f.vibe` | показать LLVM IR |

См. [установку](getting-started.md) и [инструменты](tooling.md).

## Лексика

| | |
|---|---|
| комментарии | `// строка`, `/* блок */` |
| конец оператора | перевод строки (оператор оставляйте в конце строки), либо `;` |
| числа | `42`, `0xff`, `0b101`, `0o17`, `1_000`, `3.14`, `1e9` |
| символ | `'a'` — это число `u8` |
| строки | `"text"`, escapes `\n \t \r \0 \e \\ \" \' \{ \}` |
| интерполяция | `"x = {expr}"`, литеральные скобки `{{` `}}` |

См. [лексику](lexical.md).

## Типы

| | |
|---|---|
| целые | `i8 i16 i32 i64 isize`, `u8 u16 u32 u64 usize` |
| дробные | `f32 f64` |
| прочее | `bool`, `void`, `str` (= `[]u8`) |
| указатель | `*T`, `*void`, `null` |
| срез / массив | `[]T`, `[N]T` |
| ошибка / опционал | `!T`, `?T` |
| функции | `fn(A, B) R`, замыкание `fn[](A) R` |
| псевдоним | `type Имя = Тип` |

См. [типы](types.md).

## Переменные

```vibe run
const N = 4 * 2
var counter: i64 = 0

fn main() {
    let a = 10
    var b: i64 = 20
    b += a
    var zero: i32
    counter += 1
    println(a, b, zero, N, counter)
}
```

`let` — неизменяемая, `var` — изменяемая, без значения — ноль. См. [переменные](variables.md).

## Операторы

| | |
|---|---|
| арифметика | `+ - * / %`, `-x` |
| сравнение | `== != < <= > >=` |
| логика | `&& \|\| !` (ленивые, только `bool`) |
| биты | `& \| ^ ~ << >>` |
| присваивание | `= += -= *= /= %=`, `_ = выражение` |
| приведение | `x as T` |
| указатели | `&x`, `*p`, `p[i]`, `p + n`, `p.поле` |
| срезы | `x[a..b]`, `x[a..]`, `x[..b]`, `x[..]` |
| проверка варианта | `x is .Вариант` |
| ошибка / опционал | `f()?`, `f() catch v`, `f() catch \|e\| { ... }`, `x orelse v` |

Приоритет, от слабого к сильному: `catch`/`orelse`, `||`, `&&`, сравнения, `|`, `^`, `&`, сдвиги, `+ -`, `* / %`, `as`, унарные, постфиксные. См. [операторы](operators.md).

## Управление потоком

```vibe run
fn main() {
    let n = 7
    if n > 5 { println("big") } else { println("small") }

    var i = 0
    while i < 2 { i += 1 }

    for k in 0..3 { print(k, "") }
    println()
    for idx, v in [10, 20] { print("{idx}={v}", "") }
    println()

    let word = match n {
        1, 2 => "few",
        _ => "many",
    }
    println(word, i)
}
```

| | |
|---|---|
| `if c { } else if c { } else { }` | условие — только `bool`, скобки блока обязательны |
| `while c { }` | цикл |
| `for i in a..b { }` | `a` включительно, `b` нет |
| `for x in seq { }`, `for i, x in seq { }` | массив, срез, `List` |
| `break`, `continue`, `return [e]` | выходы |
| `match v { pat => e, ... }` | значения, enum, строки, union; `_` — остальное |
| `defer stmt`, `errdefer stmt` | выполнить при выходе из блока (`errdefer` — только при ошибке) |

См. [управление потоком](control-flow.md).

## Функции

```vibe run
fn add(a: i64, b: i64) i64 { return a + b }
fn largest[T: Ord](a: T, b: T) T { if a > b { return a } return b }

fn main() {
    let k = 10
    let plus = fn[k](x: i64) i64 { return x + k }
    println(add(1, 2), largest(3, 9), plus(5))
}
```

| | |
|---|---|
| объявление | `fn имя(п: Т) Результат { }` |
| дженерик | `fn имя[T](x: T) T`, ограничения `Eq Ord Num Int Float` |
| явный тип | `имя[i64](...)` |
| замыкание | `fn[захват](x: i64) i64 { }`, живёт только вниз по стеку |
| C | `extern fn f(x: i64) i64`, `export fn g() { }` |

См. [функции](functions.md).

## Структуры, union, enum

```vibe run
struct Point { x: i64, y: i64 }
enum Color { Red, Green }
union Shape { Circle: f64, Empty }

impl Point {
    fn new(x: i64, y: i64) Self { return Self{ x: x, y: y } }
    fn sum(self) i64 { return self.x + self.y }
}

fn main() {
    let p = Point.new(1, 2)
    let c: Color = .Green
    let s: Shape = .Circle(2.0)
    println(p.sum(), c, s)
    match s {
        .Circle(r) => println("r = {r}")
        .Empty => {}
    }
}
```

| | |
|---|---|
| литерал | `P{ x: 1, y: 2 }`, `P{ x: 1, .. }` (остальное нулями), `P{ .. }` |
| метод | `impl P { fn m(self) ... }`, `self` = `*Self`, `self: Self` — копия |
| статический | `fn new() Self`, вызов `P.new()` |
| enum | `.Имя` (по контексту) или `Color.Red`; `as i64` |
| union | `.Имя(payload)`, `.Имя`; `match` с привязкой |
| дженерик | `struct Pair[A, B] { ... }`, `impl Pair[A, B] { ... }` |

См. [структуры, union и enum](structs-unions-enums.md).

## Ошибки и опционалы

```vibe run
fn half(n: i64) !i64 {
    if n % 2 != 0 { return error.Odd }
    return n / 2
}

fn find(xs: []i64, v: i64) ?i64 {
    for i, x in xs { if x == v { return i } }
    return null
}

fn main() {
    println(half(8) catch 0, half(7) catch 0)
    println(find([4, 5], 5) orelse -1)
}
```

См. [ошибки и опциональные значения](errors-and-optionals.md).

## Память

| | |
|---|---|
| аллокаторы | `c_allocator()`, `FixedBuf.init(buf).allocator()`, `Arena.init(parent).allocator()` |
| выделить | `a.alloc[T](n)?`, `a.create[T]()?`, `a.dup(s)?` |
| освободить | `a.free(s)`, `a.destroy(p)`, `arena.deinit()` |
| шаблон | `let x = a.alloc[T](n)?` и сразу `defer a.free(x)` |

См. [память](memory.md).

## Коллекции

```vibe run
fn main() !void {
    var xs = List[i64].init(c_allocator())
    defer xs.deinit()
    xs.push(3)?
    xs.push(1)?
    xs.sort()
    println(xs.slice())

    var m = Map[i64].init(c_allocator())
    defer m.deinit()
    m.put("a", 1)?
    println(m.get("a")?, m.has("b"))
}
```

См. [коллекции](collections.md).

## Строки и вывод

| | |
|---|---|
| вывод | `print`, `println`, `eprint`, `eprintln` |
| в буфер | `bprint(buf[..], "...")?`, `sprint(&list, "...")?` |
| форматы | `{x:x}` `{x:08X}` `{x:6}` `{x:-6}` `{f:.2}` `{f:e}` `{c:c}` |
| строки | `s.len`, `s[i]`, `s[a..b]`, `==`, `str_find`, `str_trim`, `parse_int` |
| паника | `panic("msg {x}")`, `assert(cond)` |

См. [строки](strings.md).

## Модули и C

```text
import "util.vibe"                  имена в общее пространство
import "util.vibe" as u             u.имя
vibe run main.vibe lib.c x.cpp -lm  C и C++ вместе
```

См. [модули](modules.md) и [C](c-interop.md).

## Тесты

```vibe test
test "арифметика" {
    assert(1 + 1 == 2)
}
```

`vibe test main.vibe`. См. [тестирование](testing.md).

## Ловушки одной строкой

- Литерал вне диапазона типа обрезается молча, целые переполняются молча.
- Деление целого на ноль роняет программу.
- `catch` и `orelse` забирают всё правее: ставьте скобки.
- `{` в строке — интерполяция, литеральная скобка — `{{`.
- Замыкание нельзя возвращать, функции без `return` на всех путях компилируются.
- Имена прелюдии (`min`, `max`, `abs`, `sort`, `run`, `env`) заняты.

Полный список: [ловушки и FAQ](gotchas.md).
