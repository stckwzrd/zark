---
title: Справочник стандартной библиотеки
order: 40
section: Справочник
description: Все функции и типы прелюдии Vibe: вывод, строки, числа, аллокаторы, List, Map, Option, файлы, процессы, время и математика
---

Стандартная библиотека — один файл `src/std.vibe`, написанный на самом Vibe. Он подключается к каждой программе **автоматически** (прелюдия). Ничего импортировать не нужно.

Имена из прелюдии занимают общее пространство имён с вашими: свою функцию с именем `min`, `max`, `abs`, `sort`, `swap`, `run`, `env`, `cstr`, `arg` и т. п. объявить нельзя, будет ошибка «duplicate function».

Имена с префиксом `__` (`__find`, `__qsort`) внутренние. Не вызывайте их.

Обозначения: `!T` — функция может вернуть ошибку; `a` — значение типа `Allocator`.

## Вывод и форматирование

Это **встроенные** функции компилятора. Формат: `println("x = {x}")`, подробности — на странице [строки](strings.md#форматирование).

| Функция | Что делает |
|---|---|
| `print(...)` | печатает аргументы через пробел |
| `println(...)` | то же и перевод строки |
| `eprint(...)`, `eprintln(...)` | то же в stderr |
| `bprint(buf: []u8, ...) !str` | форматирует в буфер; `error.NoSpace`, если не влезло |
| `sprint(out: *List[u8], ...) !void` | дописывает в список |
| `panic(msg)` | печатает сообщение и место, завершает с кодом 1 |
| `assert(cond)` | `panic` с местом, если `cond` ложно |
| `embed("файл")` | байты файла как константа `str`, читается при компиляции |
| `sizeof(T)`, `alignof(T)` | размер и выравнивание типа, `u64`, при компиляции |

## Аллокаторы

```vibe
struct Allocator {
    ctx: *void
    alloc_fn: fn(*void, u64, u64) *void
    free_fn: fn(*void, *void, u64)
}
```

| Функция | Что делает |
|---|---|
| `c_allocator() Allocator` | `calloc` / `free` |
| `a.alloc[T](n) ![]T` | `n` элементов, зануленных; `error.OutOfMemory` |
| `a.free(slice)` | освобождает срез от `alloc` |
| `a.create[T]() !*T` | один зануленный `T` |
| `a.destroy(p)` | освобождает `create` |
| `a.dup(s: str) !str` | копия строки |
| `a.dupz(s: str) !*u8` | копия с нулевым байтом, для C |

### `FixedBuf`

| Функция | Что делает |
|---|---|
| `FixedBuf.init(buf: []u8)` | аллокатор поверх вашего буфера |
| `fb.allocator() Allocator` | сам аллокатор |
| `fb.reset()` | считает весь буфер свободным |
| `fb.remaining() i64` | сколько байт осталось |

### `Arena`

| Функция | Что делает |
|---|---|
| `Arena.init(parent: Allocator)` | арена поверх родителя |
| `ar.allocator() Allocator` | сам аллокатор |
| `ar.deinit()` | освобождает всё разом |

Подробнее: [память](memory.md).

## `List[T]`

| Метод | Что делает |
|---|---|
| `List[T].init(a)` | пустой список |
| `deinit()` | освобождает буфер |
| `reserve(n) !void` | выделяет ёмкость |
| `push(v) !void` | добавляет |
| `append(xs: []T) !void` | добавляет несколько |
| `pop() !T` | убирает последний, `error.Empty` |
| `last() !T` | последний, `error.Empty` |
| `get(i) T` | элемент |
| `set(i, v)` | записывает |
| `slice() []T` | элементы как срез |
| `is_empty() bool` | пуст ли |
| `clear()` | длина в ноль |
| `contains(v) bool` | есть ли |
| `reverse()` | разворот |
| `sort()` | сортировка |
| поля `items`, `len`, `a` | буфер, число элементов, аллокатор |

## `Map[V]`

| Метод | Что делает |
|---|---|
| `Map[V].init(a)` | пустая таблица |
| `deinit()` | освобождает память |
| `put(key: str, v) !void` | вставка или замена |
| `get(key: str) !V` | значение, `error.NotFound` |
| `has(key: str) bool` | есть ли ключ |
| поля `len`, `entries` | число ключей; записи `{ key, value, used }` |

Ключи не копируются.

## `Option[T]`

```vibe
union Option[T] {
    Some: T
    None
}
```

`?T` — запись для `Option[T]`.

| Метод | Что делает |
|---|---|
| `is_some() bool` | есть ли значение |
| `unwrap_or(d) T` | значение или `d` |

## Математические и общие функции

| Функция | Что делает |
|---|---|
| `min(a, b)`, `max(a, b)` | меньшее, большее |
| `abs(x)` | модуль числа |
| `swap(a: *T, b: *T)` | обмен значений |
| `sort(s: []T)` | сортировка на месте |
| `sqrt`, `sin`, `cos`, `tan`, `exp`, `log` | `f64 → f64` |
| `pow(x, y)` | степень |
| `floor`, `ceil`, `fabs` | округление вниз, вверх, модуль |
| `PI` | 3.141592653589793 |

```vibe run
fn main() {
    println(sqrt(16.0), sin(0.0), cos(0.0), floor(2.7), ceil(2.1), fabs(-3.0))
    println(exp(0.0), log(1.0), pow(2.0, 10.0), PI)
    println(min(3, 4), max(3.5, 1.0), abs(-5))
}
```

## Строки и символы

| Функция | Что делает |
|---|---|
| `str_find(s, needle) i64` | позиция подстроки, `-1` |
| `str_find_byte(s, c) i64` | позиция байта, `-1` |
| `str_rfind_byte(s, c) i64` | последняя позиция байта, `-1` |
| `str_starts_with(s, p)`, `str_ends_with(s, p)` | начало и конец |
| `str_trim(s) str` | убрать пробелы по краям |
| `cstr(p: *u8) str` | C-строка в `str` |
| `to_cstr(buf, s) !*u8` | C-строка в вашем буфере, `error.NoSpace` |
| `is_digit`, `is_alpha`, `is_alnum`, `is_upper`, `is_hex` | классы символа (`u8`) |

## Числа из текста

| Функция | Что делает |
|---|---|
| `parse_int(s) !i64` | целое, допускает знак и пробелы; `error.InvalidNumber` |
| `parse_int_radix(s, radix) !u64` | по основанию; `radix` 0 — автоопределение `0x`, `0b`, `0o` |
| `parse_float(s) !f64` | дробное, `error.InvalidNumber` |
| `bits_f64(x) u64` | биты числа |
| `f64_from_bits(x) f64` | число из бит |

```vibe run
fn main() {
    println(parse_int(" -42 ") catch 0)
    println(parse_int("4x") catch -1)
    println(parse_int_radix("ff", 16) catch 0)
    println(parse_int_radix("0b101", 0) catch 0)
    println(parse_float("2.5e1") catch 0.0)
    println(bits_f64(1.0), f64_from_bits(4611686018427387904))
}
```

## Файлы

| Функция | Что делает |
|---|---|
| `read_file(a, path) !str` | весь файл в память; `error.FileNotFound`, `error.ReadFailed` |
| `write_file(path, data) !void` | записать с заменой; `error.CannotOpen`, `error.WriteFailed` |
| `file_exists(path) bool` | существует ли |
| `remove(path: *u8) i32` | удалить (C-функция) |
| `mkdir(path: *u8, mode: u32) i32` | создать каталог (C-функция) |

Результат `read_file` выделен через `a`: освободите его (или используйте арену).

```vibe run
fn main() !void {
    let a = c_allocator()
    write_file("demo.txt", "строка 1\nстрока 2\n")?
    println(file_exists("demo.txt"))

    let text = read_file(a, "demo.txt")?
    defer a.free(text)
    println(text.len)

    let missing = read_file(a, "net-takogo.txt") catch |e| {
        println("нет файла: {e}")
        return
    }
    println(missing.len)
}
```

## Ввод

| Функция | Что делает |
|---|---|
| `read_line(buf: []u8) !str` | одна строка из stdin без `\n`; `error.EndOfFile` |

## Процессы и окружение

| Функция | Что делает |
|---|---|
| `run(a, argv: []str) !i32` | запускает процесс, ждёт, возвращает код выхода; `error.Signaled`, если убит сигналом |
| `env(name) !str` | переменная окружения; `error.NotFound` |
| `arg_count() i64` | число аргументов (вместе с именем программы) |
| `arg(i) str` | аргумент по номеру; `arg(0)` — путь программы |
| `exit(code: i32)` | завершить программу |

```vibe run
fn main() !void {
    let a = c_allocator()
    let code = run(a, ["/bin/echo", "hi", "there"])?
    println("код", code)
    let bad = run(a, ["/bin/sh", "-c", "exit 3"])?
    println("код", bad)
    println(env("NO_SUCH_VAR_HERE") catch "не задана")
    println(arg_count())
}
```

Аргументы программы при `vibe run` идут после `--`: `vibe run main.vibe -- a b`.

## Время и случайные числа

| Функция | Что делает |
|---|---|
| `now_ns() i64` | монотонное время в наносекундах (для замеров) |
| `clock() i64` | процессорное время (C-функция) |
| `time(null) i64` | секунды Unix (C-функция) |
| `rand() i32`, `srand(seed: u32)` | генератор C |

Измерить время:

```vibe run
fn main() {
    let t0 = now_ns()
    var s = 0
    for i in 0..1000000 { s += i }
    let ms = (now_ns() - t0) as f64 / 1000000.0
    println(s, ms >= 0.0)
}
```

## Функции libc, доступные без объявления

Из C-библиотеки в прелюдии уже объявлены: `printf`, `malloc`, `calloc`, `free`, `exit`, `memcmp`, `memcpy`, `memmove`, `memset`, `strlen`, `fdopen`, `fgets`, `fopen`, `fclose`, `fread`, `fwrite`, `fseek`, `ftell`, `remove`, `mkdir`, `fork`, `execvp`, `waitpid`, `getenv`, `fflush`, `strtod`, `clock_gettime`, `clock`, `rand`, `srand`, `time` и математика. Любую другую вызывайте через `extern fn` (см. [C](c-interop.md)).

## Что дальше

- Сквозные примеры с этими функциями: [рецепты](cookbook.md).
- Если что-то не работает как ожидали: [ловушки и FAQ](gotchas.md).
