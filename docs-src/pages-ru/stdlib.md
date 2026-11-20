---
title: Справочник стандартной библиотеки
order: 40
section: Справочник
description: Все функции и типы прелюдии Vibe: вывод, строки, числа, аллокаторы, List, Map, Option, файлы, процессы, время и математика
---

Стандартная библиотека — один файл `std/std.vibe`, написанный на самом Vibe. Он подключается к каждой программе **автоматически** (прелюдия). Ничего импортировать не нужно.

Имена из прелюдии занимают общее пространство имён с вашими: свою функцию с именем `min`, `max`, `abs`, `sort`, `swap`, `run`, `env`, `cstr`, `arg` и т. п. объявить нельзя, будет ошибка «duplicate function».

Имена с префиксом `__` (`__find`, `__qsort`) внутренние. Не вызывайте их.

Сигнатуры пишутся как в коде: результат, имя, параметры. `!T` — функция может вернуть ошибку; `a` — значение типа `Allocator`.

## Вывод и форматирование

Это **встроенные** функции компилятора. Формат: `println("x = {x}")`, подробности — на странице [строки](strings.md#форматирование).

| Функция | Что делает |
|---|---|
| `print(...)` | печатает аргументы через пробел |
| `println(...)` | то же и перевод строки |
| `eprint(...)`, `eprintln(...)` | то же в stderr |
| `!str bprint(u8[] buf, ...)` | форматирует в буфер; `error.NoSpace`, если не влезло |
| `!void sprint(List<u8>* out, ...)` | дописывает в список |
| `panic(msg)` | печатает сообщение и место, завершает с кодом 1 |
| `assert(cond)` | `panic` с местом, если `cond` ложно |
| `embed("файл")` | байты файла как константа `str`, читается при компиляции |
| `sizeof(T)`, `alignof(T)` | размер и выравнивание типа, `u64`, при компиляции |

## Аллокаторы

```vibe
struct Allocator {
    void* ctx;
    fn(void*, u64, u64) -> void* alloc_fn;
    fn(void*, void*, u64) free_fn;
}
```

| Функция | Что делает |
|---|---|
| `Allocator c_allocator()` | `calloc` / `free` |
| `!T[] a.alloc<T>(i64 n)` | `n` элементов, зануленных; `error.OutOfMemory` |
| `a.free(slice)` | освобождает срез от `alloc` |
| `!T* a.create<T>()` | один зануленный `T` |
| `a.destroy(p)` | освобождает `create` |
| `!str a.dup(str s)` | копия строки |
| `!u8* a.dupz(str s)` | копия с нулевым байтом, для C |

### `FixedBuf`

| Функция | Что делает |
|---|---|
| `FixedBuf FixedBuf::init(u8[] buf)` | аллокатор поверх вашего буфера |
| `Allocator fb.allocator()` | сам аллокатор |
| `fb.reset()` | считает весь буфер свободным |
| `i64 fb.remaining()` | сколько байт осталось |

### `Arena`

| Функция | Что делает |
|---|---|
| `Arena Arena::init(Allocator parent)` | арена поверх родителя |
| `Allocator ar.allocator()` | сам аллокатор |
| `ar.deinit()` | освобождает всё разом |

Подробнее: [память](memory.md).

## `List<T>`

| Метод | Что делает |
|---|---|
| `List<T>::init(a)` | пустой список |
| `deinit()` | освобождает буфер |
| `!void reserve(n)` | выделяет ёмкость |
| `!void push(v)` | добавляет |
| `!void append(T[] xs)` | добавляет несколько |
| `!T pop()` | убирает последний, `error.Empty` |
| `!T last()` | последний, `error.Empty` |
| `T get(i)` | элемент |
| `set(i, v)` | записывает |
| `T[] slice()` | элементы как срез |
| `bool is_empty()` | пуст ли |
| `clear()` | длина в ноль |
| `bool contains(v)` | есть ли |
| `reverse()` | разворот |
| `sort()` | сортировка |
| поля `items`, `len`, `a` | буфер, число элементов, аллокатор |

## `Map<V>`

| Метод | Что делает |
|---|---|
| `Map<V>::init(a)` | пустая таблица |
| `deinit()` | освобождает память |
| `!void put(str key, v)` | вставка или замена |
| `!V get(str key)` | значение, `error.NotFound` |
| `bool has(str key)` | есть ли ключ |
| поля `len`, `entries` | число ключей; записи `{ key, value, used }` |

Ключи не копируются.

## `Option<T>`

```vibe
union Option<T> {
    T Some;
    None;
}
```

`?T` — запись для `Option<T>`.

| Метод | Что делает |
|---|---|
| `bool is_some()` | есть ли значение |
| `T unwrap_or(d)` | значение или `d` |

## Математические и общие функции

| Функция | Что делает |
|---|---|
| `min(a, b)`, `max(a, b)` | меньшее, большее |
| `abs(x)` | модуль числа |
| `void swap(T* a, T* b)` | обмен значений |
| `void sort(T[] s)` | сортировка на месте |
| `sqrt`, `sin`, `cos`, `tan`, `exp`, `log` | `f64 → f64` |
| `pow(x, y)` | степень |
| `floor`, `ceil`, `fabs` | округление вниз, вверх, модуль |
| `PI` | 3.141592653589793 |

```vibe run
void main() {
    println(sqrt(16.0), sin(0.0), cos(0.0), floor(2.7), ceil(2.1), fabs(-3.0));
    println(exp(0.0), log(1.0), pow(2.0, 10.0), PI);
    println(min(3, 4), max(3.5, 1.0), abs(-5));
}
```

## Строки и символы

| Функция | Что делает |
|---|---|
| `i64 str_find(s, needle)` | позиция подстроки, `-1` |
| `i64 str_find_byte(s, c)` | позиция байта, `-1` |
| `i64 str_rfind_byte(s, c)` | последняя позиция байта, `-1` |
| `str_starts_with(s, p)`, `str_ends_with(s, p)` | начало и конец |
| `str str_trim(s)` | убрать пробелы по краям |
| `str cstr(u8* p)` | C-строка в `str` |
| `!u8* to_cstr(buf, s)` | C-строка в вашем буфере, `error.NoSpace` |
| `is_digit`, `is_alpha`, `is_alnum`, `is_upper`, `is_hex` | классы символа (`u8`) |

## Числа из текста

| Функция | Что делает |
|---|---|
| `!i64 parse_int(s)` | целое, допускает знак и пробелы; `error.InvalidNumber` |
| `!u64 parse_int_radix(s, radix)` | по основанию; `radix` 0 — автоопределение `0x`, `0b`, `0o` |
| `!f64 parse_float(s)` | дробное, `error.InvalidNumber` |
| `u64 bits_f64(x)` | биты числа |
| `f64 f64_from_bits(x)` | число из бит |

```vibe run
void main() {
    println(parse_int(" -42 ") catch 0);
    println(parse_int("4x") catch -1);
    println(parse_int_radix("ff", 16) catch 0);
    println(parse_int_radix("0b101", 0) catch 0);
    println(parse_float("2.5e1") catch 0.0);
    println(bits_f64(1.0), f64_from_bits(4611686018427387904));
}
```

## Файлы

| Функция | Что делает |
|---|---|
| `!str read_file(a, path)` | весь файл в память; `error.FileNotFound`, `error.ReadFailed` |
| `!void write_file(path, data)` | записать с заменой; `error.CannotOpen`, `error.WriteFailed` |
| `bool file_exists(path)` | существует ли |
| `i32 remove(u8* path)` | удалить (C-функция) |
| `i32 mkdir(u8* path, u32 mode)` | создать каталог (C-функция) |

Результат `read_file` выделен через `a`: освободите его (или используйте арену).

```vibe run
!void main() {
    const auto a = c_allocator();
    write_file("demo.txt", "строка 1\nстрока 2\n")?;
    println(file_exists("demo.txt"));

    const auto text = read_file(a, "demo.txt")?;
    defer a.free(text);
    println(text.len);

    const auto missing = read_file(a, "net-takogo.txt") catch |e| {
        println("нет файла: {e}");
        return;
    };
    println(missing.len);
}
```

## Ввод

| Функция | Что делает |
|---|---|
| `!str read_line(u8[] buf)` | одна строка из stdin без `\n`; `error.EndOfFile` |

## Процессы и окружение

| Функция | Что делает |
|---|---|
| `!i32 run(a, str[] argv)` | запускает процесс, ждёт, возвращает код выхода; `error.Signaled`, если убит сигналом |
| `!str env(name)` | переменная окружения; `error.NotFound` |
| `i64 arg_count()` | число аргументов (вместе с именем программы) |
| `str arg(i)` | аргумент по номеру; `arg(0)` — путь программы |
| `void exit(i32 code)` | завершить программу |

```vibe run
!void main() {
    const auto a = c_allocator();
    const auto code = run(a, ["/bin/echo", "hi", "there"])?;
    println("код", code);
    const auto bad = run(a, ["/bin/sh", "-c", "exit 3"])?;
    println("код", bad);
    println(env("NO_SUCH_VAR_HERE") catch "не задана");
    println(arg_count());
}
```

Аргументы программы при `vibe run` идут после `--`: `vibe run main.vibe -- a b`.

## Время и случайные числа

| Функция | Что делает |
|---|---|
| `i64 now_ns()` | монотонное время в наносекундах (для замеров) |
| `i64 clock()` | процессорное время (C-функция) |
| `i64 time(null)` | секунды Unix (C-функция) |
| `i32 rand()`, `srand(u32 seed)` | генератор C |

Измерить время:

```vibe run
void main() {
    const auto t0 = now_ns();
    auto s = 0;
    for (auto i : 0..1000000) { s += i; }
    const auto ms = (now_ns() - t0) as f64 / 1000000.0;
    println(s, ms >= 0.0);
}
```

## Функции libc, доступные без объявления

Из C-библиотеки в прелюдии уже объявлены: `printf`, `malloc`, `calloc`, `free`, `exit`, `memcmp`, `memcpy`, `memmove`, `memset`, `strlen`, `fdopen`, `fgets`, `fopen`, `fclose`, `fread`, `fwrite`, `fseek`, `ftell`, `remove`, `mkdir`, `fork`, `execvp`, `waitpid`, `getenv`, `fflush`, `strtod`, `clock_gettime`, `clock`, `rand`, `srand`, `time` и математика. Любую другую вызывайте через `extern fn` (см. [C](c-interop.md)).

## Что дальше

- Сквозные примеры с этими функциями: [рецепты](cookbook.md).
- Если что-то не работает как ожидали: [ловушки и FAQ](gotchas.md).
