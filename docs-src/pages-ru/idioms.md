---
title: Пишем идиоматично на Vibe
order: 20.6
section: Память и данные
description: Как строить программы на Vibe: конструкторы и очистка, аллокаторы, ошибки, моделирование данных, тесты и привычки, которыми довольны проверки компилятора
---

Язык позволяет написать программу многими способами. Эта страница показывает способ, который работает вместе с проверками компилятора, а не против них, и который узнают другие программисты на Vibe. Каждый пример здесь компилируется и запускается.

## Имена и раскладка

Типы пишутся `PascalCase`, функции, методы, переменные и поля — `snake_case`, константы — `UPPER_CASE`. Файлы — `snake_case.vibe`. Функция, строящая значение, называется `init` или `new` (и `static`), а освобождающая — `deinit`. Держите вместе в одном файле типы и функции, которые идут вместе, и подключайте файл через `as`, если имена могут столкнуться ([модули](modules.md)).

## Тип, владеющий памятью: `init`, `deinit`, `errdefer`

Схема всегда одна: конструктор берёт аллокатор, запоминает его и убирает за собой, если последующий шаг не удался. Деструктор помечен `move`, поэтому использовать значение после него — ошибка компиляции.

```vibe run
struct Buffer {
    Allocator a;
    u8[] data;
    i64 used;

    static !Buffer init(Allocator a, i64 capacity) {
        const auto data = a.alloc<u8>(capacity)?;
        return Buffer{ .a = a, .data = data };
    }

    void deinit() move {
        this->a.free(this->data);
    }

    !void put(u8 b) {
        if (this->used == this->data.len) { return error.Full; }
        this->data[this->used] = b;
        this->used += 1;
    }

    str text() borrows {
        return this->data[0..this->used];
    }
}

!void main() {
    auto buf = Buffer::init(c_allocator(), 8)?;
    defer buf.deinit();
    for (auto c : "vibe") { buf.put(c)?; }
    println(buf.text());
}
```

Обратите внимание на три вещи. Буфер хранит аллокатор, с которым создан, поэтому `deinit` не нужен аргумент и он не может освободить не тем. `text()` помечен `borrows`: вызывающему, который сохранил результат и затем изменил буфер, об этом скажут. Тому, кто забыл `deinit`, поможет `DebugAllocator` в тестах.

Когда у конструктора несколько шагов, каждый шаг с выделением получает `errdefer`, который его откатывает. Он срабатывает только если функция возвращает ошибку:

```vibe run
struct Pair {
    i64* left;
    i64* right;
}

!Pair make_pair(Allocator a) {
    const auto left = a.create<i64>()?;
    errdefer a.destroy(left);
    const auto right = a.create<i64>()?;
    return Pair{ .left = left, .right = right };
}

void main() {
    const auto a = c_allocator();
    const auto p = make_pair(a) catch return;
    *p.left = 1;
    *p.right = 2;
    println(*p.left + *p.right);
    a.destroy(p.left);
    a.destroy(p.right);
}
```

Если второе выделение не удалось, первое освобождается при выходе. Если оба удались, `errdefer` ничего не делает, и вызывающий владеет обоими.

## Передавайте аллокатор, выбирайте время жизни

Функция, которая выделяет, принимает `Allocator` первым параметром. Она не выбирает, откуда берётся память, поэтому вызывающий может дать ей арену, фиксированный буфер или отладочный аллокатор.

Группируйте то, что живёт и умирает вместе, в одной арене. Запрос, кадр, единица компиляции, тест: одна арена, один `defer arena.deinit()`.

```vibe run
!str[] split_words(Allocator a, str text) {
    auto out = List<str>::init(a);
    auto start = 0;
    for (auto i : 0..text.len + 1) {
        if (i == text.len || text[i] == ' ') {
            if (i > start) { out.push(text[start..i])?; }
            start = i + 1;
        }
    }
    return out.slice();
}

!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto words = split_words(arena.allocator(), "one two  three")?;
    println(words.len, words);
}
```

`split_words` ничего не освобождает: результат — срез в памяти арены, и арена отдаёт всё разом. Сравните с функцией, которая вернула бы `List`, и вызывающему пришлось бы помнить про `deinit`.

## Принимайте срезы, возвращайте значения

На входе берите самое общее представление данных: `str` вместо списка символов, `T[]` вместо `List<T>`. Тогда функция работает с массивами, списками и частями обоих и не может перевыделить то, что ей дали.

```vibe run
i64 sum(i64[] xs) {
    auto total = 0;
    for (auto x : xs) { total += x; }
    return total;
}

void main() {
    auto arr = [1, 2, 3, 4];
    auto list = List<i64>::init(c_allocator());
    defer list.deinit();
    for (auto x : arr) { list.push(x * 10) catch return; }
    println(sum(arr[..]), sum(arr[1..3]), sum(list.slice()));
}
```

На выходе возвращайте небольшие значения и структуры по значению. Выходной параметр используйте только для чего-то большого, что уже существует (буфер для заполнения).

## Ошибки: давайте им имена и сохраняйте их

Возвращайте именованную ошибку из места, которое понимает проблему. Передавайте ошибки выше через `?`, где лучше не получится, и превращайте через `catch` только там, где знают, что делать.

```vibe run exit
!i64 read_port(str s) {
    const auto n = parse_int(s) catch { return error.BadPort; };
    if (n < 1 || n > 65535) { return error.PortOutOfRange; }
    return n;
}

!void main() {
    println(read_port("8080")?);
    println(read_port("99999") catch |e| { println("config problem: {e}"); 0; });
    println(read_port("http")?);
}
```

`main` возвращает `!void`, поэтому необработанная ошибка становится сообщением о завершении программы, как показывает последняя строка. Не используйте `catch 0`, чтобы заглушить ошибку, если ноль на самом деле не правильный ответ.

Используйте `?T` для «может ничего не быть» и `!T` для «может не получиться». Поиск, который ничего не нашёл, — не ошибка:

```vibe run
?str find_name(str[] names, str prefix) {
    for (auto n : names) {
        if (n.len >= prefix.len && n[0..prefix.len] == prefix) { return n; }
    }
    return null;
}

void main() {
    const str[3] names = ["ada", "alan", "grace"];
    println(find_name(names[..], "al") orelse "nobody");
    println(find_name(names[..], "zz") orelse "nobody");
}
```

## Моделируйте данные через union и enum

Делайте невозможные состояния невозможными. Запрос, который либо ждёт, либо выполняется с прогрессом, либо завершён с результатом, — это union, а не три булевых значения:

```vibe run
union Job {
    Waiting;
    f64 Running;
    i64 Done;
    str Failed;
}

str progress_text(f64 p) {
    if (p > 0.5) { return "more than half"; }
    return "just started";
}

str result_text(i64 n) {
    if (n > 0) { return "done, has a result"; }
    return "done, empty";
}

str describe(Job j) {
    return match j {
        .Waiting => "waiting",
        .Running(p) => progress_text(p),
        .Done(n) => result_text(n),
        .Failed(why) => why,
    }
}

void main() {
    println(describe(.Waiting));
    println(describe(.Running(0.8)));
    println(describe(.Done(0)));
    println(describe(.Failed("disk full")));
}
```

Когда вы добавляете вариант, каждый `match` без ветки `_` перестаёт компилироваться, пока вы его не обработаете. Так компилятор работает как чек-лист. Избегайте веток `_ =>` в `match` по своим типам: они прячут именно эту помощь.

## Пусть нулевое значение будет полезным

Литерал структуры задаёт названное и обнуляет остальное, а переменные начинаются с нуля. Проектируйте тип так, чтобы полностью нулевое значение было корректным пустым, и тогда не нужны ни конструктор, ни флаг «инициализировано»:

```vibe run
struct Stats {
    i64 count;
    i64 total;
    i64 max;

    void add(i64 x) {
        this->count += 1;
        this->total += x;
        if (x > this->max) { this->max = x; }
    }

    f64 mean() {
        if (this->count == 0) { return 0.0; }
        return this->total as f64 / this->count as f64;
    }
}

void main() {
    auto s = Stats{};
    for (auto x : [4, 8, 15, 16, 23, 42]) { s.add(x); }
    println(s.count, s.max, s.mean());
}
```

Типы с аллокатором — исключение: им нужен `init`. У нулевого `List` нет аллокатора, и `push` на нём возвращает `error.NoAllocator`, а не падает.

## Интерфейсы на краях

Ставьте интерфейс там, где программа встречается с миром: файлы, сеть, часы, лог. Логика принимает интерфейс, программа передаёт настоящее, тест — подделку. Никакой фреймворк не нужен.

```vibe test
interface Clock {
    i64 now();
}

struct FakeClock {
    i64 t;
    i64 now() { return this->t; }
}

bool expired(Clock c, i64 deadline) {
    return c.now() >= deadline;
}

test "a deadline in the future is not expired" {
    auto fake = FakeClock{ .t = 100 };
    assert(!expired(&fake, 200));
}

test "a deadline in the past is expired" {
    auto fake = FakeClock{ .t = 300 };
    assert(expired(&fake, 200));
}
```

## Делайте и не делайте

| Делайте | Не делайте |
|---|---|
| `defer a.free(x)` на строке после выделения | освобождать в конце функции вручную |
| принимать `str` и `T[]` | принимать `List<T>*`, когда только читаете |
| `?`, чтобы передавать ошибки выше | `catch 0`, чтобы предупреждение исчезло |
| `match` без `_` по своим union | универсальная ветка, скрывающая новые варианты |
| брать указатель на элемент списка поздно, отпускать рано | держать `list.at(i)` через `push` (компилятор откажет) |
| одна арена на единицу работы | глобальный аллокатор, которым никто не владеет |
| `+%` для хешей | `+`, когда ждёте заворачивания (он паникует намеренно) |
| `comptime assert(sizeof(T) == N)` для раскладок | комментарий «должно быть 16 байт» |
| `defer t.join()` или `errdefer t.join()` сразу после каждого `spawn` | `join` только в самом конце, так что `?` может оставить поток работать (компилятор откажет) |
| собрать изменения и применить после цикла | `list.push(...)` внутри `for (auto x : list)` (компилятор откажет) |

## Что дальше

- Потренируйтесь на небольших задачах: [курс](learn.md).
- Полный список проверок: [модель безопасности](safety.md).
- Когда сообщение непонятно: [отладка](debugging.md).
