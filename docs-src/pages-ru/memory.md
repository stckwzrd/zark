---
title: Память и аллокаторы
order: 20
section: Память и данные
description: Стек и куча, явный Allocator, c_allocator, FixedBuf, Arena, create/destroy, свой аллокатор и типичные ошибки работы с памятью в Zark
---

Главное правило языка: **ничто не выделяет память само.** Ни строки, ни интерполяция, ни замыкания, ни `println`. Куча появляется только там, где вы явно передали **аллокатор**. Поэтому, читая код, вы всегда видите, кто, где и сколько берёт.

## Стек и куча

Обычные переменные, массивы и структуры живут на **стеке** функции и исчезают при выходе из неё. Для данных, которые нужно сохранить дольше или размер которых неизвестен заранее, нужна **куча**, а к ней доступ через аллокатор.

```zark run
void main() {
    i64[4] local;
    local[0] = 1;
    println(local, sizeof(u8[256]));
}
```

Массив фиксированного размера на стеке — самый дешёвый способ получить память. Но размер должен быть известен при компиляции, а вернуть такой массив срезом из функции нельзя: после возврата стек освободится.

## Allocator

`Allocator` — маленькая структура из трёх полей: контекст и две функции.

```zark
struct Allocator {
    void* ctx;
    fn(void*, u64, u64) -> void* alloc_fn;
    fn(void*, void*, u64) free_fn;
}
```

Любой аллокатор — это такие три значения. Готовые аллокаторы из стандартной библиотеки:

| Аллокатор | Откуда берёт память | Освобождение |
|---|---|---|
| `c_allocator()` | `calloc` / `free` из libc | каждый кусок отдельно |
| `FixedBuf::init(buf)` | ваш готовый буфер, кучи нет | `reset()` для всего сразу |
| `Arena::init(parent)` | кусками у родительского аллокатора | `deinit()` для всего сразу |

И методы любого аллокатора `a`:

| Метод | Что делает |
|---|---|
| `!T[] a.alloc<T>(n)` | `n` элементов, заполненных **нулями** |
| `a.free(slice)` | освобождает срез, полученный из `alloc` |
| `!T* a.create<T>()` | один `T` в куче, нули |
| `a.destroy(p)` | освобождает `create` |
| `!str a.dup(s)` | копия строки |
| `!u8* a.dupz(s)` | копия с нулевым байтом в конце, для C |

Каждая операция выделения возвращает `!...`: когда память кончилась, вы получаете обычную ошибку `error.OutOfMemory`, а не падение.

### `alloc` и `free`

```zark run
!void main() {
    const auto a = c_allocator();
    const auto xs = a.alloc<i64>(4)?;
    defer a.free(xs);
    println(xs, xs.len);
    xs[0] = 10;
    xs[3] = 40;
    println(xs);
}
```

Память нулевая: можно читать без инициализации. Размер среза можно узнать как `xs.len`.

> **Совет.** Сразу после получения памяти пишите `defer a.free(...)`. Тогда она освободится на любом выходе из функции, даже по ошибке.

### `create` и `destroy`

Для одного объекта, например узла списка:

```zark run
struct Node {
    i64 val;
    Node* next;
}

!void main() {
    const auto a = c_allocator();
    const auto n1 = a.create<Node>()?;
    defer a.destroy(n1);
    const auto n2 = a.create<Node>()?;
    defer a.destroy(n2);
    n1.val = 1;
    n1.next = n2;
    n2.val = 2;
    println(n1.val, n1.next.val, n2.next == null);
}
```

### `dup`

```zark run
!void main() {
    const auto a = c_allocator();
    u8[3] src = [104, 105, 33];
    const auto copy = a.dup(src[..])?;
    defer a.free(copy);
    src[0] = 72;
    println(copy, src[..]);
}
```

## Ошибка нехватки памяти

В Zark нехватка памяти — не катастрофа, а значение, которое обрабатывается. Это особенно важно для `FixedBuf`, у которого память ограничена:

```zark run
void main() {
    u8[64] mem;
    auto fb = FixedBuf::init(mem[..]);
    const auto a = fb.allocator();
    println(fb.remaining());
    const auto first = a.alloc<u8>(40) catch return;
    println(first.len, fb.remaining());
    const auto second = a.alloc<u8>(40) catch |e| {
        println("не хватило: {e}");
        return;
    };
    println(second.len);
}
```

## `FixedBuf`: без кучи вообще

`FixedBuf` раздаёт память из вашего массива «по возрастающей». Отдельные куски освобождать не нужно: `free` возвращает память, только если это самое последнее выделение, иначе ничего не делает. Весь буфер возвращается одним вызовом `reset()`. Аллокатор хранит указатель на `fb`, поэтому переменная `fb` должна жить, пока вы пользуетесь аллокатором.

```zark run
!void main() {
    u8[256] mem;
    auto fb = FixedBuf::init(mem[..]);
    const auto a = fb.allocator();

    auto list = List<i64>::init(a);
    for (auto i : 0..5) { list.push(i * i)?; }
    println(list.slice(), fb.remaining());

    fb.reset();
    println(fb.remaining());
}
```

Применения: встроенные системы, обработка запроса «в рамках бюджета», функции, которые не должны трогать кучу. Весь код на `FixedBuf` работает без единого `malloc`.

> **Ловушка.** После `fb.reset()` все ранее выданные куски недействительны (на них нет защиты). Не используйте старые срезы и контейнеры после сброса: `list` выше нужно заново инициализировать.

## `Arena`: выделять много, освободить разом

`Arena` берёт крупные куски у родительского аллокатора и раздаёт из них маленькие. Куски берутся порциями от 64 КБ. Отдельные `free` ничего не делают, а `deinit()` освобождает **всё** сразу. Идеальна для данных с общим временем жизни: разбор файла, обработка одного запроса, построение дерева.

```zark run
!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto a = arena.allocator();

    auto words = List<str>::init(a);
    const auto w1 = a.dup("alpha")?;
    const auto w2 = a.dup("beta")?;
    words.push(w1)?;
    words.push(w2)?;
    println(words.slice());

    for (auto i : 0..1000) {
        _ = a.alloc<i64>(100)?;
    }
    println("тысяча массивов выделена и ни одного free");
}
```

Не нужно вызывать `list.deinit()` или `a.free(w1)`: всё уйдёт вместе с `arena.deinit()`. Именно так устроен сам компилятор Zark: одна арена на запуск.

Типичный шаблон: аллокатор передаётся параметром.

```zark run
struct Config {
    str name;
    List<i64> values;
}

!Config load(Allocator a) {
    auto cfg = Config{ .name = a.dup("config")?, .values = List<i64>::init(a) };
    for (auto i : 1..4) { cfg.values.push(i * 10)?; }
    return cfg;
}

!void main() {
    auto arena = Arena::init(c_allocator());
    defer arena.deinit();
    const auto cfg = load(arena.allocator())?;
    println(cfg.name, cfg.values.slice());
}
```

Функция `load` не знает, какой аллокатор ей дали. Вызывающий решает: арена, `FixedBuf` или `c_allocator`.

## Свой аллокатор

Достаточно заполнить три поля. Например, счётчик, который считает выделения и передаёт работу родителю:

```zark run
struct Counting {
    i64 count;
    i64 bytes;
    Allocator parent;
}

void* count_alloc(void* ctx, u64 size, u64 align) {
    const auto c = ctx as *Counting;
    c.count += 1;
    c.bytes += size as i64;
    return c.parent.alloc_fn(c.parent.ctx, size, align);
}

void count_free(void* ctx, void* p, u64 size) {
    const auto c = ctx as *Counting;
    c.parent.free_fn(c.parent.ctx, p, size);
}

!void main() {
    auto stats = Counting{ .count = 0, .bytes = 0, .parent = c_allocator() };
    const auto a = Allocator{ .ctx = &stats as *void, .alloc_fn = count_alloc, .free_fn = count_free };

    auto list = List<i64>::init(a);
    defer list.deinit();
    for (auto i : 0..20) { list.push(i)?; }
    println(list.len, stats.count, stats.bytes);
}
```

`alloc_fn(ctx, size, align)` обязана вернуть **нулевую** память или `null`, когда не хватило. `free_fn(ctx, ptr, size)` получает указатель и тот же размер.

20 элементов потребовали три выделения (8, 16 и 32 элемента по 8 байт: 64 + 128 + 256 = 448 байт): список удваивает ёмкость.

## Стековые данные и указатели

Указатель на локальную переменную нельзя возвращать:

```zark error
i64* bad() {
    auto x = 5;
    return &x;
}

void main() { println(*bad()); }
```

После выхода из `bad` стек перезаписывается, и указатель «висел» бы, поэтому компилятор такой код отклоняет. То же с срезом локального массива и с потоком, замыкание которого захватило локальную переменную (см. [указатели, пережившие свою память](#указатели-пережившие-свою-память)). Замыкание, которое вы возвращаете вручную, остаётся на вашей ответственности (см. [замыкания](functions.md#замыкания)).

Правило: данные, переживающие функцию, должны лежать в памяти, которой владеет вызывающий (параметр-срез, указатель, аллокатор).

```zark run
void fill(i64[] out) {
    for (auto i : 0..out.len) { out[i] = i * i; }
}

void main() {
    i64[5] buf;
    fill(buf[..]);
    println(buf);
}
```

## Использование после free — ошибка компиляции

Параметр можно пометить `move`: функция забирает значение, и вызывающий больше не должен использовать эту переменную. В стандартной библиотеке `move` стоит на `free`, `destroy` и на каждом `deinit`/`close`, поэтому самые частые ошибки с памятью останавливаются при компиляции.

```zark error
void main() {
    const auto a = c_allocator();
    auto p = a.create<i64>() catch return;
    *p = 7;
    a.destroy(p);
    println(*p);
}
```

То же касается двойного `free`, в том числе спрятанного за `defer`, и использования `List` после `deinit()`:

```zark error
void main() {
    const auto a = c_allocator();
    auto buf = a.alloc<u8>(16) catch return;
    defer a.free(buf);
    a.free(buf);
}
```

Присваивание нового значения возвращает переменную к жизни. Ветки учитываются: переменную, отданную на одном из путей `if`, нельзя использовать дальше, а переменную, отданную внутри цикла, нужно присвоить заново или выйти из цикла через `break`/`return`.

```zark run
void main() {
    const auto a = c_allocator();
    auto buf = a.alloc<u8>(16) catch return;
    a.free(buf);
    buf = a.alloc<u8>(32) catch return;
    println(buf.len);
    a.free(buf);
}
```

`move` можно использовать и в своём коде. У параметра он стоит перед типом, у метода — после списка параметров:

```zark run
struct Conn {
    i64 fd;
    void close() move { println("closed {this->fd}"); }
}

void finish(move Conn* c) { c->close(); }

void main() {
    auto c = Conn{ .fd = 7 };
    finish(&c);
}
```

Проверка следит за именами, а не за памятью. Она видит `a.free(buf)` и затем `buf`, но не видит `auto copy = buf; a.free(buf); use(copy)` и не отслеживает поля (`this->items`). Для таких случаев используйте `DebugAllocator`: он останавливает программу на самом обращении.

## Указатели, пережившие свою память

Компилятор следит за тем, откуда взялись указатель или срез. Указатель на локальную переменную не может выйти из функции ни через `return`, ни через запись в параметр:

```zark error
i64* first_of() {
    i64[4] a;
    auto p = &a[1];
    return p;
}

void main() { println(*first_of()); }
```

```zark error
struct Slot { i64* p; }

void put(Slot* out) {
    i64 x = 1;
    out->p = &x;
}

void main() {
    Slot s;
    put(&s);
}
```

Указатель или срез внутрь контейнера действителен, пока контейнер не изменился. Методы, которые могут сдвинуть память (`push`, `append`, `insert`, `reserve`, `Map.put`, `remove`), помечены `invalidates`, а методы, отдающие указатель внутрь (`at`, `slice`, `get_ptr`), помечены `borrows`. Использовать такой указатель после вызова с `invalidates` — ошибка, как и использовать срез после `free` буфера, из которого он взят:

```zark error
void main() {
    auto l = List<i64>::init(c_allocator());
    defer l.deinit();
    l.push(1) catch return;
    auto p = l.at(0);
    l.push(2) catch return;
    println(*p);
}
```

Возьмите указатель заново после изменения, и всё в порядке:

```zark run
void main() {
    auto l = List<i64>::init(c_allocator());
    defer l.deinit();
    l.push(1) catch return;
    auto p = l.at(0);
    *p = 10;
    l.push(2) catch return;
    p = l.at(1);
    *p = 20;
    println(l.get(0), l.get(1));
}
```

Изменение контейнера, пока по нему идёт цикл, — та же ошибка в другом костюме: цикл продолжает читать старый буфер. Компилятор следит и за циклами `for`, а `this->items` считается так же, как локальная переменная:

```zark error
void main() {
    auto l = List<i64>::init(c_allocator());
    defer l.deinit();
    for (auto i : 0..3) { l.push(i) catch return; }
    for (auto x : l) {
        l.push(x * 10) catch return;
    }
}
```

Соберите то, что хотите добавить, и добавьте после цикла либо выйдите из цикла сразу после изменения (`break` или `return`): оба варианта принимаются.

Свои типы могут использовать те же слова после списка параметров: `T* at(i64 i) borrows { ... }` и `!void push(T v) invalidates { ... }`. Как и `move`, проверка следит за именами переменных: указатель, сохранённый в поле структуры или переданный через вызов функции, не отслеживается.

## Чего не проверяет компилятор

| Проблема | Что будет |
|---|---|
| Использование переменной после `free`, `destroy`, `deinit` | **проверяется**: ошибка компиляции |
| Использование через копию указателя или через поле | не проверяется (используйте `DebugAllocator`) |
| Указатель на локальную переменную выходит из функции | **проверяется**: ошибка компиляции |
| Указатель в `List`/`Map` после `push`/`put` | **проверяется**: ошибка компиляции |
| Двойной `free` одной переменной | **проверяется**: ошибка компиляции |
| Утечка (забыли `free`/`deinit`) | молча; память освободится при выходе процесса |
| Выход за границы среза или массива | **проверяется**: паника с файлом и строкой |
| Выход за границы через указатель | не проверяется |
| Деление на ноль | **проверяется**: паника с файлом и строкой |

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
