---
title: Шпаргалка
order: 44
section: Справочник
description: Весь синтаксис Zark на одной странице: таблицы и короткие примеры для быстрого поиска
---

Краткая памятка. Подробности по каждой теме — по ссылкам.

## Программа

```zark run
void main() {
    println("Привет, Zark!");
}
```

| Команда | Что делает |
|---|---|
| `zark run f.zk [-- args]` | собрать и запустить |
| `zark build f.zk [-o out] [--release]` | собрать исполняемый файл |
| `zark test f.zk` | запустить блоки `test` |
| `zark fmt [--check] f.zk` | отформатировать |
| `zark lsp` | языковой сервер |
| `zark ir f.zk` | показать LLVM IR |

См. [установку](getting-started.md) и [инструменты](tooling.md).

## Лексика

| | |
|---|---|
| комментарии | `// строка`, `/* блок */` |
| конец оператора | `;` (после `}` блока не нужна) |
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
| прочее | `bool`, `void`, `str` (= `u8[]`) |
| указатель | `T*`, `void*`, `null` |
| срез / массив | `T[]`, `T[N]` |
| ошибка / опционал | `!T`, `?T` |
| функции | `fn(A, B) -> R`, замыкание `fn[](A) -> R` |
| псевдоним | `type Имя = Тип;` |
| SIMD | `f32x4`, `i32x8`, `u8x16`: `f32x4(a, b, c, d)`, `f32x4(x)`, `v[i]` |

См. [типы](types.md).

## Переменные

```zark run
const auto N = 4 * 2;
i64 counter = 0;

void main() {
    const auto a = 10;
    i64 b = 20;
    b += a;
    i32 zero;
    counter += 1;
    println(a, b, zero, N, counter);
}
```

Переменная изменяема, `const` делает её неизменяемой, `auto` выводит тип, без значения — ноль. См. [переменные](variables.md).

## Операторы

| | |
|---|---|
| арифметика | `+ - * / %`, `-x` (переполнение и деление на ноль паникуют) |
| заворачивание | `+% -% *%` (никогда не паникуют) |
| сравнение | `== != < <= > >=` |
| логика | `&& \|\| !` (ленивые, только `bool`) |
| биты | `& \| ^ ~ << >>` |
| присваивание | `= += -= *= /= %= |= &= ^= <<= >>=`, `x++`, `x--`, `_ = выражение` |
| приведение | `x as T` |
| указатели | `&x`, `*p`, `p[i]`, `p + n`, `p.поле` |
| срезы | `x[a..b]`, `x[a..]`, `x[..b]`, `x[..]` |
| проверка варианта | `x is .Вариант` |
| ошибка / опционал | `f()?`, `f() catch v`, `f() catch \|e\| { ... }`, `x orelse v` |

Приоритет, от слабого к сильному: `catch`/`orelse`, `||`, `&&`, сравнения, `|`, `^`, `&`, сдвиги, `+ -`, `* / %`, `as`, унарные, постфиксные. См. [операторы](operators.md).

## Управление потоком

```zark run
void main() {
    const auto n = 7;
    if (n > 5) { println("big"); } else { println("small"); }

    auto i = 0;
    while (i < 2) { i += 1; }

    for (auto k : 0..3) { print(k, ""); }
    println();
    for (auto [idx, v] : [10, 20]) { print("{idx}={v}", ""); }
    println();

    const auto word = match n {
        1, 2 => "few",
        _ => "many",
    };
    println(word, i);
}
```

| | |
|---|---|
| `if (c) { } else if (c) { } else { }` | условие — только `bool`, скобки блока обязательны |
| `while (c) { }` | цикл |
| `for (auto i : a..b) { }` | `a` включительно, `b` нет |
| `for (auto x : seq) { }`, `for (auto [i, x] : seq) { }` | массив, срез, `List` |
| `break`, `continue`, `return [e]` | выходы |
| `match v { pat => e, ... }` | значения, enum, строки, union; `_` — остальное |
| `defer stmt`, `errdefer stmt` | выполнить при выходе из блока (`errdefer` — только при ошибке) |

См. [управление потоком](control-flow.md).

## Функции

```zark run
i64 add(i64 a, i64 b) { return a + b; }
template<T: Ord> T largest(T a, T b) { if (a > b) { return a; } return b; }

void main() {
    const auto k = 10;
    const auto plus = [&k](i64 x) -> i64 { return x + k; };
    println(add(1, 2), largest(3, 9), plus(5));
}
```

| | |
|---|---|
| объявление | `Результат имя(Тип п) { }` |
| дженерик | `template<T: Ord> T имя(T x)`, ограничения `Eq Ord Num Int Float` |
| явный тип | `имя<i64>(...)` |
| замыкание | `[&захват](i64 x) -> i64 { }`, живёт только вниз по стеку |
| C | `extern i64 f(i64 x);`, `export void g() { }` |

См. [функции](functions.md).

## Структуры, union, enum

```zark run
struct Point {
    i64 x;
    i64 y;
    static Self new(i64 x, i64 y) { return Self{ .x = x, .y = y }; }
    i64 sum() { return this->x + this->y; }
}
enum Color { Red, Green }
union Shape { f64 Circle; Empty; }

void main() {
    const auto p = Point::new(1, 2);
    const Color c = .Green;
    const Shape s = .Circle(2.0);
    println(p.sum(), c, s);
    match s {
        .Circle(r) => println("r = {r}");
        .Empty => {}
    }
}
```

| | |
|---|---|
| литерал | `P{ .x = 1, .y = 2 }`, `P{ .x = 1 }` (остальное нулями), `P{}` |
| метод | внутри `struct`: `void m() { ... }`, `this` — указатель |
| статический | `static Self new() { ... }`, вызов `P::new()` |
| enum | `.Имя` (по контексту) или `Color::Red`; `as i64` |
| union | `.Имя(payload)`, `.Имя`; `match` с привязкой |
| дженерик | `struct Pair<A, B> { ... }`, `Pair<i64, str>{ ... }` |

См. [структуры, union и enum](structs-unions-enums.md).

## Ошибки и опционалы

```zark run
!i64 half(i64 n) {
    if (n % 2 != 0) { return error.Odd; }
    return n / 2;
}

?i64 find(i64[] xs, i64 v) {
    for (auto [i, x] : xs) { if (x == v) { return i; } }
    return null;
}

void main() {
    println(half(8) catch 0, half(7) catch 0);
    println(find([4, 5], 5) orelse -1);
}
```

См. [ошибки и опциональные значения](errors-and-optionals.md).

## Память

| | |
|---|---|
| аллокаторы | `c_allocator()`, `FixedBuf::init(buf).allocator()`, `Arena::init(parent).allocator()` |
| выделить | `a.alloc<T>(n)?`, `a.create<T>()?`, `a.dup(s)?` |
| освободить | `a.free(s)`, `a.destroy(p)`, `arena.deinit()` |
| шаблон | `auto x = a.alloc<T>(n)?;` и сразу `defer a.free(x)` |
| владение | `void deinit() move { ... }`, `void f(move T* p)`: после вызова переменная мертва |
| заимствование | `T* at(i64 i) borrows { ... }`, `!void push(T v) invalidates { ... }` |
| тип-ресурс | `owned struct Thread { ... }`: в каждой области его нужно присоединить или передать дальше |
| при компиляции | `comptime f(3)`, `const auto T = comptime make_table();`, `comptime assert(sizeof(S) == 16);` |

См. [память](memory.md).

## Коллекции

```zark run
!void main() {
    auto xs = List<i64>::init(c_allocator());
    defer xs.deinit();
    xs.push(3)?;
    xs.push(1)?;
    xs.sort();
    println(xs.slice());

    auto m = Map<i64>::init(c_allocator());
    defer m.deinit();
    m.put("a", 1)?;
    println(m.get("a")?, m.has("b"));
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
import "util.zk";                 имена в общее пространство
import "util.zk" as u;            u::имя
zark run main.zk lib.c x.cpp -lm  C и C++ вместе
```

См. [модули](modules.md) и [C](c-interop.md).

## Тесты

```zark test
test "арифметика" {
    assert(1 + 1 == 2);
}
```

`zark test main.zk`. См. [тестирование](testing.md).

## Ловушки одной строкой

- Литерал вне диапазона типа — ошибка компиляции, а переполнение целых в безопасной сборке — паника (для намеренного заворачивания пишите `+%`, `-%`, `*%`; `--release` убирает проверку).
- Деление целого на ноль — паника (в `--release` не проверяется).
- `catch` и `orelse` забирают всё правее: ставьте скобки.
- `{` в строке — интерполяция, литеральная скобка — `{{`.
- Замыкание не должно пережить захваченные переменные; функция без `return` на каждом пути не компилируется.
- Имена прелюдии (`min`, `max`, `abs`, `sort`, `run`, `env`) заняты.

Полный список: [ловушки и FAQ](gotchas.md).
