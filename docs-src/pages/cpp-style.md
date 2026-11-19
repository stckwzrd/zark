---
title: Синтаксис в стиле C++
order: 3
section: Старт
description: Как писать на Vibe в привычном для C++ виде: типы впереди, template, методы внутри struct, лямбды, for с круглыми скобками
---

Vibe понимает два способа записи одной и той же программы. Первый, с `fn`, `let`, `var` и `impl`, описан на остальных страницах. Второй выглядит как C++ и описан здесь. Они дают одинаковое дерево программы и одинаковый код, их можно смешивать в одном проекте, но не внутри одного объявления.

## Объявления: тип впереди

```vibe run
const i64 LIMIT = 4;
i64 counter = 0;

i64 add(i64 a, i64 b) {
    return a + b;
}

i32 main() {
    auto n = add(2, 3);
    const i64 k = 10;
    i64 acc;
    acc = n * k;
    counter++;
    println(n, k, acc, LIMIT, counter);
    return 0;
}
```

Правила:

- Тип пишется перед именем: `i64 x = 5;`. Вместо типа можно написать `auto`.
- Переменные и параметры **изменяемы** по умолчанию. `const` делает значение неизменяемым, как `let`.
- Результат функции стоит перед её именем. Функция без результата называется `void`.
- Точка с запятой ставится как в C++. Компилятор по-прежнему вставляет её в конце строки сам, поэтому оператор нельзя переносить в начало следующей строки.
- `nullptr` — то же, что `null`.

Типы: `T*` указатель, `T[]` срез, `T[N]` массив, `!T` ошибка, `?T` опциональное значение. Для встроенных типов (`i64[4]`, `u8[]`) размер в скобках всегда массив. Для своих типов размер должен быть числом: `Point[4]`, потому что `Name[T]` в старой записи значит дженерик.

## Структуры и методы внутри struct

```vibe run
struct Point {
    i64 x;
    i64 y;

    i64 len2() const { return x * x + y * y; }
    void move(i64 dx, i64 dy) { x += dx; this->y += dy; }
    static Point origin() { return Point{}; }
}

i32 main() {
    auto p = Point{ .x = 3, .y = 4 };
    p.move(1, 1);
    println(p.len2(), p, Point::origin());
    return 0;
}
```

- Методы лежат внутри `struct`. Поля доступны по голому имени (`x`) и через `this->x` (или `this.x`). Локальная переменная с тем же именем перекрывает поле.
- `static` объявляет функцию без `this`: `Point::origin()`.
- `const` после списка параметров принимается, но пока **не проверяется**: константный метод всё ещё может менять поля.
- Литерал с точками, `Point{ .x = 3 }`, обнуляет остальные поля, как в C++. `Point{}` — все поля нулевые.

## Union, enum и `::`

```vibe run
union Shape {
    f64 Circle;
    i64 Rect;
    Empty;
}

enum Color { Red, Green }

f64 area(Shape s) {
    return match s {
        .Circle(r) => r * r * 3.0,
        .Rect(w) => w as f64,
        .Empty => 0.0,
    };
}

i32 main() {
    Shape s = Shape::Circle(2.0);
    Color c = Color::Green;
    println(area(s), c);
    return 0;
}
```

Варианты union пишутся как поля: `тип Имя;`. Вариант без данных — просто `Имя;`. `::` равнозначно `.`: `Color::Green`, `net::connect(...)`, `Point::origin()`.

## Шаблоны

```vibe run
struct Pair<A, B> {
    A first;
    B second;
    A get_first() { return first; }
}

template<T: Ord> T largest(T a, T b) {
    if (a > b) { return a; }
    return b;
}

i32 main() {
    auto q = Pair<i64, str>{ .first = 7, .second = "seven" };
    println(q.get_first(), q);
    println(largest(3, 9), largest<f64>(2.5, 1.5));
    return 0;
}
```

Параметры обобщённых функций пишутся в `template<...>`, обобщённых типов — прямо после имени: `struct Pair<A, B>`. Ограничения: `T: Ord`. Явные аргументы: `largest<f64>(...)`, `List<i64>::init(a)`.

## Управление потоком

В `if` и `while` условие в круглых скобках, фигурные скобки остаются обязательными.

```vibe run
i64 sum(i64[] xs) {
    i64 total = 0;
    for (i64 x : xs) { total += x; }
    return total;
}

i32 main() {
    i64[4] arr = [1, 2, 3, 4];
    i64 acc = 0;
    for (i64 i = 0; i < 10; i++) {
        if (i % 2 == 0) { continue; }
        acc += i;
    }
    for (i64 i : 0..3) { acc += i; }
    acc <<= 1;
    acc |= 1;
    println(sum(arr[..]), acc);
    return 0;
}
```

Формы `for`:

- `for (T x : seq)` — перебор массива, среза или списка;
- `for (T i : a..b)` — диапазон от `a` до `b`, `b` не включается;
- `for (T i = a; i < b; i++)` и `i <= b`, шаг только `i++`, `++i` или `i += 1`. Это тот же диапазон. Любые другие C-циклы пишите через `while`.

Появились `++`, `--` и все составные присваивания: `+= -= *= /= %= |= &= ^= <<= >>=`. `i++` — оператор, а не выражение.

`match` остаётся прежним, как и `defer`, `errdefer`, `?`, `catch`, `orelse`, `is`, интерполяция строк и `as`.

## Ошибки и опциональные значения

```vibe run
!i64 parse(str s) {
    if (s.len == 0) { return error.Empty; }
    return parse_int(s);
}

?i64 find(i64[] xs, i64 want) {
    for (i64 i = 0; i < xs.len; i++) {
        if (xs[i] == want) { return i; }
    }
    return nullptr;
}

i32 main() {
    i64[3] xs = [4, 5, 6];
    println(parse("12") catch -1, parse("") catch -1);
    println(find(xs[..], 6) orelse -1, find(xs[..], 9) orelse -1);
    return 0;
}
```

## Лямбды

Захват записывается как в C++, `[&k]`: переменные захватываются **по ссылке**, контекст лежит на стеке, замыкание нельзя возвращать из функции.

```vibe run
i32 main() {
    i64 n = 10;
    i64 calls = 0;
    auto add = [&n, &calls](i64 x) -> i64 {
        calls++;
        return x + n;
    };
    println(add(5), add(6), calls);
    return 0;
}
```

Тип замыкания пишется `fn[](i64) -> i64`, функции — `fn(i64) -> i64`.

## Модули

```vibe file=cpp_lib.vibe
i64 twice(i64 x) { return x * 2; }
```

```vibe run
import "cpp_lib.vibe" as lib;

i32 main() {
    println(lib::twice(21));
    return 0;
}
```

## Что пока не так, как в C++

- Нет `class`, `public:`, конструкторов и деструкторов, наследования и перегрузки.
- Нет `switch`: используйте `match`.
- Нет тернарного `?:`.
- Нет `int`, `long`, `double`: размер всегда виден в имени (`i32`, `i64`, `f64`).
- Приведение — `x as T`, а не `(T)x` и не `static_cast`.
- В приведении указатель пишется префиксом: `p as *u8`.
- `const` у метода не проверяется.

Остальные страницы руководства написаны в прежней записи. Таблица соответствия:

| C++-вид | Прежняя запись |
|---|---|
| `i64 add(i64 a, i64 b)` | `fn add(a: i64, b: i64) i64` |
| `auto x = 1;` / `const i64 x = 1;` | `var x = 1` / `let x: i64 = 1` |
| `i64* p`, `i64[]`, `i64[4]` | `*i64`, `[]i64`, `[4]i64` |
| `struct P { i64 f() const {...} }` | `struct P {...}` и `impl P { fn f(self) i64 {...} }` |
| `template<T> T f(T a)` | `fn f[T](a: T) T` |
| `List<i64>::init(a)` | `List[i64].init(a)` |
| `[&k](i64 x) -> i64 {...}` | `fn[k](x: i64) i64 {...}` |
| `for (i64 i = 0; i < n; i++)` | `for i in 0..n` |
