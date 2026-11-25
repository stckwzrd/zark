---
title: "Учим Zark: путь от нуля до программы"
order: 1.5
section: Старт
description: Пошаговый курс из двенадцати уроков с упражнениями и решениями: как думать на Zark, писать код, который компилятор принимает с первого раза, и закончить настоящей утилитой
---

Эта страница — курс. В каждом уроке короткая программа, которую можно запустить, одна мысль, на которую стоит обратить внимание, и упражнение с решением. Проходите уроки по порядку и набирайте код руками, а не копируйте: сообщения компилятора — часть обучения.

Нужен собранный компилятор, как описано в разделе [установка](getting-started.md). Кладите каждую программу в файл, например `lesson.zk`, и запускайте `zark run lesson.zk`.

Как устроен курс:

| Уроки | Тема | Что вы сможете после этого |
|---|---|---|
| 1–3 | значения, типы, управление потоком, функции | писать небольшие вычисления и скрипты |
| 4–5 | структуры, union, ошибки | описывать данные и обрабатывать сбои |
| 6–8 | память, срезы, владение | пользоваться кучей без страха |
| 9–10 | интерфейсы, замыкания, шаблоны | делить код между типами |
| 11–12 | тесты, comptime, целая утилита | выпускать законченную программу |

> **Как учиться по этой странице:** прежде чем запускать пример, скажите вслух, что он, по-вашему, напечатает. Если результат удивил, остановитесь и разберитесь почему: это удивление и есть урок.

## Урок 1. Значения и печать

Всё начинается в `main`. `println` печатает аргументы через пробел; внутри строки выражение в фигурных скобках вычисляется и подставляется.

```zark run
void main() {
    const auto name = "Zark";
    auto year = 2026;
    year += 1;
    println("Hello, {name}! Next year is {year}.");
    println(name.len, year, 7 / 2, 7 % 2, 7.0 / 2.0);
}
```

Обратите внимание на три вещи. `const` запрещает менять переменную, а обычная форма разрешает. `auto` позволяет компилятору вывести тип. `7 / 2` — это `3`, потому что целочисленное деление отбрасывает дробную часть.

**Упражнение.** Напечатайте среднее из `3`, `4` и `8` числом с двумя знаками после запятой. Подсказка: преобразуйте до деления и используйте `{x:.2}` в строке.

```zark run
void main() {
    const auto sum = 3 + 4 + 8;
    const auto avg = sum as f64 / 3 as f64;
    println("average = {avg:.2}");
}
```

## Урок 2. Типы и почему преобразования видны

У целых есть размер и знак: `i8`, `i16`, `i32`, `i64` и `u8` … `u64`. Дробные — `f32` и `f64`. Значение само переходит в больший тип того же рода, а всё остальное требует `as`.

```zark run
void main() {
    const i32 small = 70000;
    const i64 wide = small;
    const auto back = wide as i16;
    println(wide, back);
    println(3.99 as i64, -1 as u8, 300.5 as u8);
}
```

`wide as i16` оставляет только то, что поместилось (`4464`). Дробное вне диапазона целого типа не делает ничего опасного: оно становится ближайшей границей (`300.5 as u8` — это `255`).

Арифметике, которая не помещается, нельзя пройти незамеченной. В обычной сборке она останавливает программу сообщением с файлом и строкой:

```zark run exit
void main() {
    u8 level = 250;
    for (auto i : 0..10) {
        level += 1;
        println(level);
    }
}
```

Когда заворачивание — именно то, что вам нужно (хеш, счётчик, идущий по кругу), скажите об этом через `+%`, `-%` и `*%`.

```zark run
void main() {
    u8 level = 250;
    for (auto i : 0..10) { level = level +% 1; }
    println(level);
}
```

**Упражнение.** Что делает `200 as u8 + 100 as u8`? Запишите ответ, потом запустите.

```zark run exit
void main() {
    const u8 a = 200;
    const u8 b = 100;
    println(a + b);
}
```

Ответ — паника, а не `44`. Чтобы получить `44`, напишите `a +% b`.

## Урок 3. Управление потоком и функции

`if`, `while` и `for` работают так, как вы ожидаете. Диапазон `a..b` включает `a` и не включает `b`. У функции тип результата стоит перед именем.

```zark run
bool is_prime(i64 n) {
    if (n < 2) { return false; }
    for (auto d : 2..n) {
        if (d * d > n) { break; }
        if (n % d == 0) { return false; }
    }
    return true;
}

void main() {
    for (auto n : 1..30) {
        if (is_prime(n)) { print("{n} "); }
    }
    println("");
}
```

Обратите внимание: переменную цикла `d` создаёт сам цикл, и внутри его нельзя менять, а `break` выходит только из ближайшего цикла.

**Упражнение.** Напишите `gcd(a, b)` по алгоритму Евклида и напечатайте `gcd(48, 18)`.

```zark run
i64 gcd(i64 a, i64 b) {
    while (b != 0) {
        const auto t = a % b;
        a = b;
        b = t;
    }
    return a;
}

void main() {
    println(gcd(48, 18));
}
```

Параметры — копии, поэтому изменение `a` и `b` внутри функции не трогает переменные вызывающего.

## Урок 4. Структуры, методы и union

Структура группирует поля. Методы пишутся внутри неё и используют `this`. Литерал называет поля, которые задаёт, а всё остальное — ноль.

```zark run
struct Account {
    str owner;
    i64 cents;

    static Account open(str owner) {
        return Account{ .owner = owner };
    }

    void deposit(i64 amount) {
        this->cents += amount;
    }

    str describe() {
        return this->owner;
    }
}

void main() {
    auto acc = Account::open("Ada");
    acc.deposit(1500);
    acc.deposit(250);
    println(acc.describe(), acc.cents);
}
```

Когда значение может иметь одну из нескольких разных форм, используйте `union`: он несёт метку, а `match` заставляет обработать каждую форму.

```zark run
union Cmd {
    i64 Push;
    Pop;
    Add;
}

void main() {
    const Cmd[4] program = [.Push(2), .Push(40), .Add, .Pop];
    i64[16] stack;
    auto top = 0;
    for (auto c : program) {
        match c {
            .Push(v) => { stack[top] = v; top += 1; }
            .Add => { stack[top - 2] = stack[top - 2] + stack[top - 1]; top -= 1; }
            .Pop => { top -= 1; println("popped {stack[top]}"); }
        }
    }
}
```

Оператор `match` может пропускать варианты: для них ничего не происходит. `match`, который даёт значение, обязан покрыть каждый вариант, и компилятор назовёт пропущенный. В этом смысл выбора такой формы, когда забытый случай был бы багом: когда вы добавляете в union новый вариант, каждое такое место перестаёт компилироваться, пока вы его не обработаете.

```zark error
union Shape {
    f64 Circle;
    i64 Square;
    Empty;
}

f64 area(Shape s) {
    return match s {
        .Circle(r) => 3.14 * r * r,
        .Square(w) => w as f64,
    }
}

void main() { println(area(.Empty)); }
```

**Упражнение.** Добавьте команду `Dup`, которая дублирует вершину стека, и используйте её в программе.

```zark run
union Cmd {
    i64 Push;
    Dup;
    Add;
    Print;
}

void main() {
    const Cmd[5] program = [.Push(21), .Dup, .Add, .Print, .Print];
    i64[16] stack;
    auto top = 0;
    for (auto c : program) {
        match c {
            .Push(v) => { stack[top] = v; top += 1; }
            .Dup => { stack[top] = stack[top - 1]; top += 1; }
            .Add => { stack[top - 2] = stack[top - 2] + stack[top - 1]; top -= 1; }
            .Print => { println(stack[top - 1]); }
        }
    }
}
```

## Урок 5. Ошибки — это значения

Функция, которая может не удаться, возвращает `!T`. Вызывающий обязан что-то с этим сделать: передать выше через `?`, подставить значение по умолчанию через `catch` или посмотреть через `catch |e|`. Проигнорировать результат нельзя — не скомпилируется.

```zark run exit
!i64 parse_age(str s) {
    const auto n = parse_int(s)?;
    if (n < 0 || n > 150) { return error.OutOfRange; }
    return n;
}

!void main() {
    println(parse_age("42")?);
    println(parse_age("200") catch -1);
    println(parse_age("old") catch |e| { println("could not parse: {e}"); -2; });
    println(parse_age("-5")?);
    println("not reached");
}
```

Последний вызов возвращает ошибку из `main`, и программа заканчивается сообщением `error: OutOfRange` и кодом неудачи. Ничего не бросалось, стек не раскручивался: ошибка — это просто возвращаемое значение, которое вы передали дальше.

Ошибка — не паника. Ошибки — для того, что может случиться в правильной программе: нет файла, плохой ввод, нет памяти. Паника — для бага: индекс вне диапазона, деление на ноль, переполнение. Панику нельзя перехватить, и это сделано намеренно.

**Упражнение.** Напишите `!i64 safe_div(i64 a, i64 b)`, которая возвращает `error.DivideByZero` вместо паники.

```zark run
!i64 safe_div(i64 a, i64 b) {
    if (b == 0) { return error.DivideByZero; }
    return a / b;
}

void main() {
    println(safe_div(10, 2) catch 0);
    println(safe_div(1, 0) catch -1);
}
```

## Урок 6. Память ваша, а компилятор помогает

Ничто в Zark не выделяет память за вашей спиной. Чтобы получить кучу, вы держите аллокатор и передаёте его туда, где он нужен. `defer` ставит очистку рядом с выделением, поэтому её нельзя забыть, и выполняет её как бы ни закончилась функция.

```zark run
!void main() {
    const auto a = c_allocator();
    auto numbers = List<i64>::init(a);
    defer numbers.deinit();

    for (auto i : 1..6) { numbers.push(i * i)?; }
    println(numbers.slice(), numbers.len);

    const auto one = a.create<i64>()?;
    defer a.destroy(one);
    *one = 7;
    println(*one);
}
```

Теперь о том, что делает Zark удобным. Ошибки, из-за которых падают программы на C, отклоняются при компиляции. Освободите что-то и затем используйте — компилятор укажет точную строку:

```zark error
void main() {
    const auto a = c_allocator();
    auto p = a.create<i64>() catch return;
    *p = 7;
    a.destroy(p);
    println(*p);
}
```

Освободите что-то дважды, даже через `defer`, — и это тоже отклонено. Держите указатель на элемент списка, а потом добавьте в список (буфер мог переехать) — отклонено:

```zark error
void main() {
    auto l = List<i64>::init(c_allocator());
    defer l.deinit();
    l.push(1) catch return;
    auto first = l.at(0);
    l.push(2) catch return;
    println(*first);
}
```

Исправление написано в сообщении: возьмите указатель заново после изменения.

```zark run
void main() {
    auto l = List<i64>::init(c_allocator());
    defer l.deinit();
    l.push(1) catch return;
    l.push(2) catch return;
    auto first = l.at(0);
    *first = 10;
    println(l.get(0), l.get(1));
}
```

Когда вы создаёте много мелких объектов с одним временем жизни, не освобождайте их по одному. Используйте арену: выделяйте свободно и освобождайте всё одним `deinit`.

```zark run
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    auto words = List<str>::init(a);
    for (auto w : ["alpha", "beta", "gamma"]) { words.push(a.dup(w)?)?; }
    println(words.slice());
}
```

**Упражнение.** Функция ниже течёт на пути ошибки. Исправьте её так, чтобы ничего не терялось, если второе выделение не удалось.

```zark run
!i64 sum_two(Allocator a) {
    const auto x = a.create<i64>()?;
    defer a.destroy(x);
    const auto y = a.create<i64>()?;
    defer a.destroy(y);
    *x = 20;
    *y = 22;
    return *x + *y;
}

void main() {
    println(sum_two(c_allocator()) catch 0);
}
```

Ставить `defer` сразу после каждого выделения — вся техника. Если память должна пережить успешный возврат из функции, используйте `errdefer`: он срабатывает только когда функция возвращает ошибку.

## Урок 7. Срезы и строки

Срез `T[]` — это указатель и длина: окно в память, которой владеет кто-то другой. `str` — срез байтов. Срез никогда не копирует. Каждый доступ проверяется: индекс вне диапазона — паника с позицией, а не тихое чтение чужой памяти.

```zark run
void main() {
    const auto s = "hello, world";
    const auto word = s[7..];
    println(word, word.len, s[0..5]);
    const auto xs = [10, 20, 30, 40];
    println(xs[1..3], xs[..2]);
}
```



```zark run exit
void main() {
    const auto xs = [1, 2, 3];
    auto i = 3;
    println(xs[i]);
}
```

Поскольку срез только одалживает память, компилятор следит, откуда он взялся. Срез локального массива нельзя вернуть из функции, ведь массив умирает вместе с функцией:

```zark error
u8[] first_four() {
    u8[16] buf;
    return buf[0..4];
}

void main() { println(first_four().len); }
```

Выход тот же, что в любом языке с ручной памятью: вызывающий предоставляет место, либо функция выделяет его аллокатором, который ей передали.

**Упражнение.** Напишите `count_words(str s)`, которая возвращает число слов, разделённых пробелами. Используйте только индексацию и цикл.

```zark run
i64 count_words(str s) {
    auto n = 0;
    auto in_word = false;
    for (auto c : s) {
        if (c == ' ') {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            n += 1;
        }
    }
    return n;
}

void main() {
    println(count_words("to be or not to be"), count_words("  "), count_words(""));
}
```

## Урок 8. Читаем компилятор

Программы на этом языке пишутся вместе с компилятором, поэтому научитесь его читать. В каждом сообщении есть файл, строка, строка исходника с кареткой под нужным местом и обычно подсказка, как исправить. Три привычки ускоряют работу.

1. Читайте только **первую** ошибку. Остальные часто лишь её следствия.
2. Читайте **каретку**, а не только текст: она показывает, о каком выражении речь.
3. Когда в сообщении «consumed» или «points into», оно описывает, *когда* что-то перестало быть действительным. Смотрите на названную строку.

Короткий каталог сообщений, которые встретятся в первую неделю:

```zark error
void main() {
    const i64 big = 5;
    const i32 small = big;
}
```

Сужение требует `as`. Компилятор никогда не предполагает, что вы согласны потерять биты.

```zark error
void main() {
    const auto x = 10;
    x = 11;
}
```

`const` значит константа. Уберите его, если переменная должна меняться.

```zark error
!i64 half(i64 n) {
    if (n % 2 != 0) { return error.Odd; }
    return n / 2;
}

void main() {
    half(4);
}
```

Тип «значение или ошибка» нельзя молча выбросить. Используйте `?`, `catch` или `_ =`, чтобы сказать, чего вы хотите.

```zark error
void main() {
    auto n = 5;
    println(comptime n + 1);
}
```

`comptime` выполняется при компиляции, поэтому не видит переменных, существующих только во время работы программы (урок 11).

## Урок 9. Интерфейсы

Интерфейс — это список методов. Любую структуру с такими методами можно использовать через него, без объявления связи. Вызов идёт через указатель, поэтому объект должен пережить значение интерфейса.

```zark run
interface Sink {
    void write(str s);
}

struct Counter {
    i64 bytes;
    void write(str s) { this->bytes += s.len; }
}

struct Echo {
    void write(str s) { print(s); }
}

void log_all(Sink sink, str[] lines) {
    for (auto l : lines) {
        sink.write(l);
        sink.write("\n");
    }
}

void main() {
    auto c = Counter{};
    auto e = Echo{};
    const str[2] lines = ["first", "second"];
    log_all(&e, lines[..]);
    log_all(&c, lines[..]);
    println("counted {c.bytes} bytes");
}
```

Обратите внимание: `log_all` ничего не знает про `Counter` и `Echo`. Так код становится тестируемым: в тесте передайте `Counter`, в программе — `Echo`.

**Упражнение.** Добавьте приёмник `Prefixed`, который пишет префикс перед каждой полученной строкой. Не связывайте его с `Echo`.

```zark run
interface Sink {
    void write(str s);
}

struct Echo {
    void write(str s) { print(s); }
}

struct Prefixed {
    Sink inner;
    str prefix;
    void write(str s) {
        this->inner.write(this->prefix);
        this->inner.write(s);
    }
}

void main() {
    auto e = Echo{};
    auto p = Prefixed{ .inner = &e, .prefix = "> " };
    p.write("hello\n");
}
```

## Урок 10. Замыкания и шаблоны

Замыкание перечисляет переменные, которые использует, и способ: `[&k]` — ссылка. Контекст лежит на стеке, ничего не выделяется, поэтому замыкание не должно пережить переменные, на которые указывает.

```zark run
void each(i64[] xs, fn[](i64) -> void body) {
    for (auto x : xs) { body(x); }
}

void main() {
    const auto xs = [3, 1, 4, 1, 5];
    auto total = 0;
    auto biggest = 0;
    each(xs[..], [&total, &biggest](i64 x) -> void {
        total += x;
        if (x > biggest) { biggest = x; }
    });
    println(total, biggest);
}
```

Функция или структура может быть обобщённой через `template<T>`. Ограничение вроде `T: Ord` говорит, что тип должен поддерживать. Тело проверяется по нему при объявлении, а вызов с неподходящим типом сообщается в месте вызова.

```zark run
template<T: Ord> T largest(T[] xs) {
    auto best = xs[0];
    for (auto x : xs) { if (x > best) { best = x; } }
    return best;
}

void main() {
    println(largest([3, 9, 2][..]), largest([1.5, 0.5][..]));
}
```

**Упражнение.** Напишите `template<T> i64 count_if(T[] xs, fn[](T) -> bool pred)` и посчитайте с её помощью чётные числа в списке.

```zark run
template<T> i64 count_if(T[] xs, fn[](T) -> bool pred) {
    auto n = 0;
    for (auto x : xs) { if (pred(x)) { n += 1; } }
    return n;
}

void main() {
    const auto xs = [1, 2, 3, 4, 5, 6];
    println(count_if(xs[..], [](i64 x) -> bool { return x % 2 == 0; }));
}
```

## Урок 11. Тесты и `comptime`

Тесты — часть языка. Блок `test` стоит рядом с проверяемым кодом и запускается через `zark test`. Пишите тест первым, когда можете: он показывает, какой интерфейс вам нужен.

```zark test
i64 clamp(i64 x, i64 lo, i64 hi) {
    if (x < lo) { return lo; }
    if (x > hi) { return hi; }
    return x;
}

test "inside the range nothing changes" {
    assert(clamp(5, 0, 10) == 5);
}

test "values are pulled to the edges" {
    assert(clamp(-3, 0, 10) == 0);
    assert(clamp(99, 0, 10) == 10);
}
```

`comptime` выполняет обычный код при компиляции. Это правильный инструмент для таблиц, которые иначе пришлось бы набирать руками, и для проверок, которые нельзя забывать:

```zark run
struct Header { u8 kind; u8 flags; u16 length; }

comptime assert(sizeof(Header) == 4);

u8[16] make_squares() {
    u8[16] t;
    for (auto i : 0..16) { t[i] = (i * i % 256) as u8; }
    return t;
}

const auto SQUARES = comptime make_squares();

void main() {
    println(SQUARES[7], SQUARES[15]);
}
```

Если кто-то добавит поле в `Header`, сборка упадёт на `comptime assert`, а формат файла не изменится втихую. См. [вычисления при компиляции](comptime.md).

**Упражнение.** Напишите тест, который проверяет, что `clamp` возвращает `lo`, когда `lo` равно `hi`.

```zark test
i64 clamp(i64 x, i64 lo, i64 hi) {
    if (x < lo) { return lo; }
    if (x > hi) { return hi; }
    return x;
}

test "a single allowed value" {
    assert(clamp(-5, 3, 3) == 3);
    assert(clamp(50, 3, 3) == 3);
}
```

## Урок 12. Целая утилита

Теперь соберём всё вместе: программа считает слова в тексте, обрабатывает каждый сбой, использует арену для всей памяти и держит логику в отдельной функции, принимающей `str`, поэтому тесту не нужен файл.

```zark run
!void count(str text, Map<i64>* counts, List<str>* order) {
    auto start = 0;
    for (auto i : 0..text.len + 1) {
        const auto end = i == text.len || text[i] == ' ' || text[i] == '\n';
        if (!end) { continue; }
        if (i > start) {
            const auto w = text[start..i];
            if (!counts.has(w)) { order.push(w)?; }
            counts.put(w, (counts.get(w) catch 0) + 1)?;
        }
        start = i + 1;
    }
}

!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    auto counts = Map<i64>::init(a);
    auto order = List<str>::init(a);
    count("to be or not to be\nthat is the question", &counts, &order)?;

    for (auto w : order) {
        println("{w}: {counts.get(w)?}");
    }
    if (order.len == 0) { return error.NoWords; }
}
```

Прочитайте программу как список привычек курса:

- вся память берётся из одной арены, которую освобождает один `defer`;
- после каждого вызова, который может не удаться, стоит `?` или `catch`;
- чистую функцию `count` легко тестировать, а `main` только соединяет части;
- ничто здесь не может прочитать за пределами строки, потому что каждый индекс проверяется.

**Финишная прямая.** Расширьте утилиту тремя шагами. Каждый учит отдельной части языка:

1. Читайте текст из файла, заданного в командной строке (`args`, `read_file`; см. [рецепты](cookbook.md)).
2. Отсортируйте результат по количеству (в [стандартной библиотеке](stdlib.md) есть `sort`).
3. Напишите тесты для `count` с пустым текстом, повторяющимися пробелами и одним очень длинным словом.

## Десять привычек

1. Ставьте `defer` или `errdefer` на строке сразу после выделения.
2. Передавайте аллокатор параметром. Не прячьте глобальный.
3. Предпочитайте срезы указателям и индексы — арифметике указателей.
4. Возвращайте ошибки, паникуйте только на багах.
5. Держите чистую логику в функциях, принимающих простые значения, и тестируйте её.
6. Делайте недопустимые состояния непредставимыми через `union` и `enum` и пусть `match` вас проверяет.
7. Используйте `+%` только там, где заворачивание — это смысл.
8. Берите указатель на элемент контейнера как можно позже и отпускайте, как только закончили.
9. Не воюйте с компилятором: если правило мешает, сообщение называет строку, где начались проблемы.
10. Включайте `-O` ради скорости, `-g` для отладки, а `--release` оставьте для программ, уже проверенных в безопасном режиме.

## Куда дальше

- Логика проверок и то, чего они не покрывают: [модель безопасности](safety.md).
- Как писать код, который приятно читать другим: [идиомы](idioms.md).
- Когда что-то не работает: [отладка](debugging.md).
- Большие программы: [витрина](showcase.md) и [рецепты](cookbook.md).
