---
title: Быстрый тур
order: 2
section: Старт
description: Весь язык Vibe на одной странице: короткие программы с настоящим выводом
---

Эта страница показывает всё основное за один присест. Подробности каждой темы — на отдельных страницах, ссылки в конце разделов.

## Переменные

Переменные изменяемы по умолчанию, `const` делает их неизменяемыми. Вместо типа можно написать `auto`: он выводится из значения.

```vibe run fragment
const auto a = 10;
auto b = 20;
b += a;
const f64 pi = 3.14159;
println("a = {a}, b = {b}, pi = {pi}");
```

Попытка изменить `const`-переменную не компилируется:

```vibe error fragment
const auto a = 10;
a = 11;
```

Подробнее: [переменные и константы](variables.md).

## Числа и преобразования

Целые и дробные типы называются как в Rust: `i8..i64`, `u8..u64`, `f32`, `f64`. Неявно расширять можно только без потерь, остальное — через `as`.

```vibe run fragment
const i32 small = 1000;
const i64 big = small;
const auto back = big as i32;
const auto f = 7 as f64 / 2.0;
const auto t = 3.99 as i64;
println(big, back, f, t);
```

Сужение без `as` не компилируется:

```vibe error fragment
const i64 big = 1000;
const i32 small = big;
```

Подробнее: [типы](types.md), [операторы](operators.md).

## Строки и форматирование

`str` — это срез байтов. Внутри `"..."` в фигурных скобках можно писать любое выражение, после двоеточия — формат.

```vibe run fragment
const auto name = "Vibe";
const auto n = 255;
println("{name} has {name.len} letters");
println("hex {n:x}, padded {n:08X}, width [{n:6}] [{n:-6}]");
println("pi ~ {3.14159265:.3}");
```

Подробнее: [строки и форматирование](strings.md).

## Управление потоком

```vibe run fragment
for (auto i : 1..6) {
    if (i % 2 == 0) {
        println("{i} чётное");
    } else {
        println("{i} нечётное");
    }
}
auto n = 3;
while (n > 0) {
    n -= 1;
}
println("n = {n}");
```

Подробнее: [управление потоком](control-flow.md).

## Функции

```vibe run
i64 square(i64 x) {
    return x * x;
}

void greet(str name) {
    println("Привет, {name}!");
}

void main() {
    greet("Vibe");
    println(square(12));
}
```

Подробнее: [функции](functions.md).

## Структуры и методы

```vibe run
struct Point {
    i64 x;
    i64 y;
    static Point new(i64 x, i64 y) {
        return Point{ .x = x, .y = y };
    }

    i64 len2() {
        return this->x * this->x + this->y * this->y;
    }
}

void main() {
    const auto p = Point::new(3, 4);
    println("{p.x},{p.y} -> {p.len2()}");
    println(p);
}
```

Подробнее: [структуры, union и enum](structs-unions-enums.md).

## Enum, union и match

```vibe run
enum Color { Red, Green, Blue }

union Shape {
    f64 Circle;
    i64 Rect;
    Empty;
}

str name(Color c) {
    return match c {
        .Red => "красный",
        .Green => "зелёный",
        .Blue => "синий",
    }
}

f64 area(Shape s) {
    return match s {
        .Circle(r) => 3.14 * r * r,
        .Rect(w) => w as f64,
        .Empty => 0.0,
    }
}

void main() {
    println(name(.Green));
    println(area(.Circle(2.0)), area(.Rect(5)), area(.Empty));
}
```

## Ошибки

Ошибка — значение. Функция, которая может завершиться ошибкой, возвращает `!T`. Оператор `?` пробрасывает ошибку вверх, `catch` — обрабатывает.

```vibe run exit
!i64 parse(str s) {
    if (s.len == 0) { return error.Empty; }
    return parse_int(s);
}

!void main() {
    println(parse("42")?);
    println(parse("") catch -1);
    println(parse("abc") catch |e| { println("ошибка: {e}"); 0; });
    const auto n = parse("x")?;
    println(n);
}
```

Последняя строка завершает программу с ошибкой: `main` вернул `error.InvalidNumber`.

Подробнее: [ошибки и опциональные значения](errors-and-optionals.md).

## Опциональные значения

`?T` — значение или ничего. `orelse` подставляет запасное.

```vibe run
?i64 find(i64[] items, i64 want) {
    for (auto [i, x] : items) {
        if (x == want) { return i; }
    }
    return null;
}

void main() {
    const auto xs = [5, 8, 13];
    println(find(xs[..], 13) orelse -1);
    println(find(xs[..], 99) orelse -1);
}
```

## Память

Ничто не выделяет память само. Куча — только через аллокатор, который вы передаёте явно.

```vibe run
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    auto list = List<i64>::init(a);
    for (auto i : 1..6) { list.push(i * i)?; }
    println(list.slice());
}
```

`defer` выполняется при выходе из области видимости: `arena.deinit()` освободит всё разом. Подробнее: [память и аллокаторы](memory.md).

## Дженерики

```vibe run
template<T: Ord> T largest(T a, T b) {
    if (a > b) { return a; }
    return b;
}

struct Pair<A, B> { A first; B second; }

void main() {
    println(largest(3, 9), largest(2.5, 1.5));
    const auto p = Pair<i64, str>{ .first = 1, .second = "один" };
    println(p.first, p.second);
}
```

## Замыкания

Замыкание явно перечисляет, какие переменные оно использует. Контекст живёт на стеке, ничего не выделяется.

```vibe run
i64 apply(fn[](i64) -> i64 f, i64 x) {
    return f(x);
}

void main() {
    const auto k = 10;
    auto calls = 0;
    const auto add = [&k, &calls](i64 x) -> i64 {
        calls += 1;
        return x + k;
    };
    println(apply(add, 1), apply(add, 2), calls);
}
```

## Тесты

```vibe test
i64 add(i64 a, i64 b) { return a + b; }

test "складывает" {
    assert(add(2, 3) == 5);
}

test "ноль нейтрален" {
    assert(add(7, 0) == 7);
}
```

Подробнее: [тесты](testing.md).

## Модули

Файл подключается через `import`. С `as` его имена получают префикс:

```vibe file=geometry.vibe
struct Rect { i64 w; i64 h; }

i64 area(Rect r) { return r.w * r.h; }
```

```vibe run
import "geometry.vibe" as geo;

void main() {
    const auto r = geo::Rect{ .w = 3, .h = 4 };
    println(geo::area(r));
}
```

Подробнее: [модули и импорт](modules.md).

## Вызов C

```vibe run
extern i32 atoi(u8* s);

void main() {
    println(atoi("1234") + 1);
}
```

Подробнее: [взаимодействие с C](c-interop.md).

## Куда дальше

- Пришли из C++? Отличия собраны на странице [Vibe для C++-программиста](cpp-style.md).
- Углубляться в порядке страниц раздела «Язык»: [лексика](lexical.md), [типы](types.md) и далее.
- Посмотреть готовые программы: [рецепты](cookbook.md).
- Если что-то ведёт себя неожиданно: [ловушки и FAQ](gotchas.md).
