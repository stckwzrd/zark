---
title: Структуры, union и enum
order: 16
section: Язык
description: struct и методы, enum, tagged union, дженерик-структуры, раскладка в памяти и разбор через match
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
    i64 x;
    i64 y;
}

void main() {
    const auto p = Point{ .x = 3, .y = 4 };
    println(p.x, p.y);
    println(p);
}
```

Поле объявляется как переменная: тип, имя, `;`. Структура печатается как `Имя{ поле: значение }`.

Все структуры раскладываются в памяти так же, как в C: поля идут по порядку, между ними добавляется выравнивание. Размер можно узнать через `sizeof`:

```vibe run
struct Small { u8 a; u8 b; u8 c; }
struct Padded { u8 a; i64 b; u8 c; }

void main() {
    println(sizeof(Small), sizeof(Padded), alignof(Padded));
}
```

Порядок полей влияет на размер: сначала крупные поля, потом мелкие, и структура будет компактнее.

### Литерал структуры

Литерал пишется как `Имя{ .поле = значение, ... }`. Он распознаётся, только если имя типа начинается с **заглавной** буквы.

Поля, которых в литерале нет, заполняются нулями. `Имя{}` — все поля нулевые:

```vibe run
struct Config {
    i64 width;
    i64 height;
    str title;
    bool visible;
}

void main() {
    const auto a = Config{ .width = 800, .height = 600, .title = "окно", .visible = true };
    const auto b = Config{ .width = 100 };
    const auto c = Config{};
    println(a);
    println(b);
    println(c.width, c.title.len);
}
```

Опечатка в имени поля — ошибка компиляции:

```vibe error
struct P { i64 x; i64 y; }

void main() {
    const auto p = P{ .x = 1, .y = 2, .w = 3 };
}
```

Значений по умолчанию в объявлении поля нет: пропущенное поле всегда ноль. Если нужны другие умолчания, пишите функцию `new`.

### Структуры копируются

Присваивание и передача в функцию копируют все поля:

```vibe run
struct P { i64 x; i64 y; }

void main() {
    auto a = P{ .x = 1, .y = 2 };
    auto b = a;
    b.x = 99;
    println(a.x, b.x);
}
```

Чтобы работать с одним объектом, передавайте указатель `P*` (поля через него читаются прямо через точку).

### Вложенные структуры и массивы

```vibe run
struct Point { i64 x; i64 y; }
struct Line { Point a; Point b; }
struct Poly { Point[3] pts; i64 n; }

void main() {
    const auto l = Line{ .a = Point{ .x = 0, .y = 0 }, .b = Point{ .x = 3, .y = 4 } };
    println(l.b.x, l);
    auto poly = Poly{};
    poly.pts[1].x = 5;
    poly.n = 2;
    println(poly);
}
```

### Ссылка на себя

Структура не может содержать **саму себя** по значению, но может содержать указатель на себя:

```vibe run
struct Node {
    i64 val;
    Node* next;
}

void main() {
    auto a = Node{ .val = 1, .next = null };
    auto b = Node{ .val = 2, .next = &a };
    println(b.next.val, a.next == null);
}
```

### Сравнение

`==` для структур не определён. Сравнивайте поля:

```vibe error
struct A { i64 x; }

void main() {
    const auto a = A{ .x = 1 };
    println(a == a);
}
```

## Методы

Функции, привязанные к типу, пишутся прямо внутри `struct`. Поля внутри метода доступны по голому имени, а также через `this`.

```vibe run
struct Counter {
    i64 n;
    static Self new() {
        return Self{ .n = 0 };
    }

    void inc() {
        this->n += 1;
    }

    i64 get() {
        return this->n;
    }
}

void main() {
    auto c = Counter::new();
    c.inc();
    c.inc();
    println(c.get());
    const auto p = &c;
    p.inc();
    println(p.get(), c.n);
}
```

- `Self` внутри `struct` — это сам тип.
- Метод с `static` — статический, без `this`: вызывается как `Тип::имя(...)`.
- Остальные методы получают `this` — **указатель** на объект — и могут менять поля. Вызывать их можно и у значения, и у указателя.
- Копии вместо указателя нет: если метод не должен менять объект, возьмите копию сами: `auto c = *this;`.

```vibe run
struct V {
    i64 n;
    void by_ptr() { this->n += 1; }
    i64 by_copy() {
        auto c = *this;
        c.n += 100;
        return c.n;
    }
}

void main() {
    auto v = V{ .n = 1 };
    v.by_ptr();
    println(v.by_copy(), v.n);
}
```

> **Ловушка.** Метод меняет объект даже тогда, когда он объявлен с `const`: компилятор отдаёт методу указатель и не проверяет изменяемость. Метод с `const` после списка параметров не может присваивать поля и вызывать неконстантные методы через `this`. Снаружи компилятор проверяет объект только при прямом присваивании `p.x = ...`: вызов метода у `const`-переменной разрешён. Если объект не должен меняться, не вызывайте на нём мутирующих методов.

## `enum`

Перечисление — набор имён. Значение хранится как целое число (порядковый номер варианта с нуля).

```vibe run
enum Color { Red, Green, Blue }

void main() {
    const Color c = .Green;
    println(c, Color::Blue, c == .Green, c != .Red);
    println(Color::Blue as i64, 1 as Color);
}
```

Литерал `.Имя` работает, когда тип известен из контекста: у `const Color c`, у параметра функции, у `return`, у второго операнда сравнения. Если контекста нет, пишите `Color::Green`.

Номера варианта задавать (`A = 5`) нельзя: всегда 0, 1, 2 и т. д.

Перебрать все значения можно через преобразование из целого:

```vibe run
enum Day { Mon, Tue, Wed }

void main() {
    for (auto i : 0..3) {
        const auto d = i as Day;
        println(i, d);
    }
}
```

> **Ловушка.** Преобразование `число as Enum` не проверяет диапазон: `7 as Day` даст значение «не из списка», а `match` на нём не найдёт совпадения.

### `match` по enum

```vibe run
enum Dir { North, East, South, West }

Dir turn(Dir d) {
    return match d {
        .North => .East,
        .East => .South,
        .South => .West,
        .West => .North,
    }
}

void main() {
    Dir d = .North;
    for (auto i : 0..5) {
        println(d);
        d = turn(d);
    }
}
```

Как `match`-выражение он обязан покрывать все варианты. Подробнее: [управление потоком](control-flow.md#match).

### Методы у enum

```vibe run
enum Level {
    Low, High;

    str label() {
        return match *this {
            .Low => "низкий",
            .High => "высокий",
        };
    }

    Level flip() {
        return match *this {
            .Low => .High,
            .High => .Low,
        };
    }
}

void main() {
    const Level l = .Low;
    println(l.label(), l.flip().label());
}
```

Внутри метода `this` — указатель, поэтому разыменовывайте: `match *this { ... }`.

## `union` — тип-сумма (tagged union)

Union хранит **один из вариантов**, и вместе с ним — тег, который говорит какой. У варианта может быть payload (данные) любого типа, а может не быть.

```vibe run
union Shape {
    f64 Circle;
    i64 Rect;
    Empty;
}

void main() {
    const Shape a = .Circle(2.5);
    const auto b = Shape::Rect(4);
    const Shape c = .Empty;
    println(a, b, c);
}
```

Раскладка: `{ i32 tag, payload }`, размер определяется самым большим вариантом.

```vibe run
union V { i64 I; f64 F; str S; N; }

void main() {
    println(sizeof(V));
}
```

### Разбор через `match`

Образец `.Вариант(имя)` привязывает payload. Привязанное значение — копия, только для чтения.

```vibe run
union Shape {
    f64 Circle;
    i64 Rect;
    Empty;
}

f64 area(Shape s) {
    return match s {
        .Circle(r) => 3.14 * r * r,
        .Rect(w) => w as f64 * w as f64,
        .Empty => 0.0,
    }
}

void main() {
    println(area(.Circle(1.0)), area(.Rect(3)), area(.Empty));
}
```

Проверка одного варианта без разбора — `is`:

```vibe run
union Msg { str Text; Quit; }

void main() {
    const Msg m = .Quit;
    println(m is .Quit, m is .Text);
}
```

### Union как состояние и результат

Union удобен там, где значение бывает разных видов. Например, разбор токена:

```vibe run
union Token {
    i64 Num;
    Plus;
    Minus;
    End;
}

void show(Token t) {
    match t {
        .Num(n) => println("число {n}");
        .Plus => println("+");
        .Minus => println("-");
        .End => println("конец");
    }
}

void main() {
    const auto toks = [Token::Num(1), Token::Plus, Token::Num(2), Token::End];
    for (auto t : toks) { show(t); }
}
```

### Методы у union

```vibe run
union Shape {
    f64 Circle;
    i64 Rect;
    static Self circle(f64 r) {
        return Self::Circle(r);
    }

    f64 area() {
        return match *this {
            .Circle(r) => r * r * 3.0,
            .Rect(w) => w as f64,
        }
    }
}

void main() {
    const auto s = Shape::circle(2.0);
    println(s.area());
}
```

## Дженерик-структуры и union

Параметры типа пишутся в угловых скобках после имени: `struct Pair<A, B>`. Методы лежат внутри, отдельно перечислять параметры не нужно.

```vibe run
struct Pair<A, B> {
    A first;
    B second;

    Pair<B, A> swap() {
        return Pair<B, A>{ .first = this->second, .second = this->first };
    }
}

void main() {
    const auto p = Pair<i64, str>{ .first = 1, .second = "один" };
    const auto q = p.swap();
    println(p);
    println(q);
}
```

Для каждой комбинации аргументов компилятор делает отдельную копию типа. Так устроены `List<T>`, `Map<V>` и `Option<T>` из [стандартной библиотеки](stdlib.md).

Структура-стек с массивом фиксированного размера и методами:

```vibe run
struct Stack<T> {
    T[4] items;
    i64 n;

    void push(T v) {
        this->items[this->n] = v;
        this->n += 1;
    }

    T top() {
        return this->items[this->n - 1];
    }
}

void main() {
    auto s = Stack<i64>{};
    s.push(3);
    s.push(4);
    println(s.top(), s.n);
}
```

Ограничения параметров записываются так же, как у функций: `struct Sorted<T: Ord> { ... }`. Нарушение ловится при создании типа.

## Что дальше

- Как хранить такие значения в куче: [память и аллокаторы](memory.md), [коллекции](collections.md).
- Как возвращать «значение или ошибку»: [ошибки и опциональные значения](errors-and-optionals.md).
