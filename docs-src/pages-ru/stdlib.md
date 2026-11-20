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
| `T* at(i)` | указатель на элемент `i` (действителен до следующего роста) |
| `i64 index_of(v)` | первый индекс `v` или -1 |
| `!void insert(i, v)` | вставляет перед позицией `i` |
| `!T remove_at(i)` | удаляет и возвращает элемент `i`, порядок сохраняется |
| `!T swap_remove(i)` | удаляет элемент `i` за O(1), на его место встаёт последний |
| `truncate(n)` | укорачивает до `n` элементов |
| `!Self clone()` | копия со своей памятью |
| `!T[] take()` | отдаёт элементы срезом точного размера, список становится пустым |
| поля `items`, `len`, `a` | буфер, число элементов, аллокатор |

## `Map<V>`

| Метод | Что делает |
|---|---|
| `Map<V>::init(a)` | пустая таблица |
| `deinit()` | освобождает память |
| `!void put(str key, v)` | вставка или замена |
| `!V get(str key)` | значение, `error.NotFound` |
| `bool has(str key)` | есть ли ключ |
| `V* get_ptr(str key)` | указатель на значение для изменения на месте или `null` |
| `V get_or(str key, d)` | значение или `d` |
| `bool remove(str key)` | удаляет; `false`, если ключа не было |
| `clear()` | удаляет всё |
| `iter()` | `auto it = m.iter(); while (it.next()) { it.key(); it.value(); }` |
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

## `HashMap<K, V>` и `HashSet<T>`

Хеш-таблица с ключами любого типа, который можно напечатать и сравнить через `==`: целые, `str`, enum и структуры с `operator==`, сравнивающим все поля. Хеш считается по самому значению (`hash_of`), ничего объявлять не нужно. Ключи не копируются.

```vibe run
enum Color { Red, Green }

!void main() {
    const auto a = c_allocator();
    auto ages = HashMap<str, i64>::init(a);
    defer ages.deinit();
    ages.put("ann", 31)?;
    ages.put("bob", 25)?;
    *ages.get_ptr("bob") += 1;
    println(ages.get("bob")?, ages.get_or("zoe", -1), ages.has("ann"), ages.remove("ann"), ages.len);

    auto seen = HashSet<Color>::init(a);
    defer seen.deinit();
    println(seen.add(Color::Red)?, seen.add(Color::Red)?, seen.len());
}
```

| Метод `HashMap<K, V>` | Что делает |
|---|---|
| `init(a)`, `deinit()` | создать, освободить |
| `!void put(k, v)` | вставляет или заменяет |
| `!V get(k)`, `V get_or(k, d)`, `V* get_ptr(k)` | чтение; `get_ptr` даёт `null`, если ключа нет |
| `bool has(k)`, `bool remove(k)`, `clear()` | |
| `iter()` | `while (it.next()) { it.key(); it.value(); it.value_ptr(); }` |
| `!List<K> keys(a)` | ключи в новом списке |
| поле `len` | число ключей |

У `HashSet<T>` есть `add` (`true`, если значения ещё не было), `has`, `remove`, `len()`, `clear()`, `iter()` и `items(a)`.

## Ещё про строки

Все эти функции возвращают срезы исходной строки или принимают `Allocator` для новой.

| Функция | Что делает |
|---|---|
| `str_split(s, sep)` | итератор: `auto it = str_split(s, ","); while (it.next()) { it.part }` |
| `str_fields(s)` | то же по пробельным промежуткам |
| `str_lines(s)` | строки без `\n` / `\r\n`: `while (it.next()) { it.line }` |
| `!List<str> str_split_all(a, s, sep)` | все части сразу |
| `!str str_join(a, str[] parts, sep)`, `str_concat(a, parts)` | склейка |
| `!str str_replace(a, s, from, to)` | замена всех вхождений |
| `!str str_repeat(a, s, n)`, `str_to_upper(a, s)`, `str_to_lower(a, s)` | |
| `str_contains`, `str_count`, `str_rfind` | поиск |
| `str_trim_start`, `str_trim_end`, `str_strip_prefix`, `str_strip_suffix` | обрезка |
| `str_eq_ignore_case`, `str_cmp`, `str_less` | сравнение (`str_less` подходит для `sort_by`) |
| `is_space`, `is_lower`, `to_lower(c)`, `to_upper(c)` | символы |

UTF-8: `utf8_len(s)` считает кодовые точки, `utf8_valid(s)`, `utf8_decode(s, i)` даёт `Rune{ code, size }`, `utf8_encode(buf, cp)`, а `utf8_runes(s)` перебирает (`it.code`, `it.at`).

```vibe run
!void main() {
    const auto a = c_allocator();
    auto it = str_split("name=Vibe;year=2026", ";");
    while (it.next()) {
        const auto eq = str_find_byte(it.part, '=');
        println(it.part[0..eq], "->", it.part[eq + 1..]);
    }
    println(str_replace(a, "a-b-c", "-", " + ")?, utf8_len("привет"));
}
```

## `sort_by`

`!void sort_by(a, T[] s, fn(T, T) -> bool less)` сортирует любой срез вашим сравнением. Сортировка устойчивая (равные элементы сохраняют порядок), аллокатор нужен для временного буфера.

```vibe run
struct User { str name; i64 age; }
bool by_age(User x, User y) { return x.age < y.age; }

!void main() {
    User[3] us = [User{ .name = "c", .age = 30 }, User{ .name = "a", .age = 20 }, User{ .name = "b", .age = 30 }];
    sort_by(c_allocator(), us[..], by_age)?;
    for (auto u : us) { print("{u.name} "); }
    println("");
}
```

## `DebugAllocator`

Аллокатор для поиска ошибок памяти в тестах и отладочных сборках. Каждый блок получает свои страницы, сразу за ним идёт недоступная страница, а освобождённые блоки остаются недоступными:

- чтение или запись за концом блока или после `free` останавливают программу с сообщением, где назван блок;
- двойной `free`, освобождение чужого указателя или освобождение с неверным размером вызывают panic;
- `deinit()` перечисляет неосвобождённые блоки и возвращает `error.MemoryLeak`;
- `fail_after_n(n)` делает так, что выделение после `n` успешных завершится ошибкой: так проверяют ветки нехватки памяти;
- `trap_id = k` останавливает отладчик там, где выделяется блок `#k`.

```vibe run
!void main() {
    auto dbg = DebugAllocator::init();
    {
        auto xs = List<i64>::init(dbg.allocator());
        defer xs.deinit();
        for (auto i : 0..100) { xs.push(i)?; }
    }
    dbg.deinit()?;
    println("no leaks");
}
```

Он медленный и тратит минимум 8 КиБ на блок, поэтому в релизных сборках его не используют.

## Сообщения о падении

Каждая программа (кроме `--freestanding`) ставит обработчик падений. Вместо голого «segmentation fault» вы получите причину и место:

```text
fatal: segmentation fault: null pointer dereference (address 0x0)
backtrace:
  #0 0x2187 in ./app
  #1 0x13ad in ./app
where (addr2line):
vb.get at /home/me/app.vibe:3
vb.main at /home/me/app.vibe:7
```

Различаются причины: нулевой указатель, переполнение стека (бесконечная рекурсия), целочисленное деление на ноль, использование после освобождения и выход за границы блока `DebugAllocator`. Строки исходника берутся из `addr2line` (binutils), если он установлен. `VIBE_CRASH_HANDLER=0` отключает обработчик (например, чтобы получить core dump).

## Функции libc, доступные без объявления

Из C-библиотеки в прелюдии уже объявлены: `printf`, `malloc`, `calloc`, `free`, `exit`, `memcmp`, `memcpy`, `memmove`, `memset`, `strlen`, `fdopen`, `fgets`, `fopen`, `fclose`, `fread`, `fwrite`, `fseek`, `ftell`, `remove`, `mkdir`, `fork`, `execvp`, `waitpid`, `getenv`, `fflush`, `strtod`, `clock_gettime`, `clock`, `rand`, `srand`, `time` и математика. Любую другую вызывайте через `extern fn` (см. [C](c-interop.md)).

## Что дальше

- Сквозные примеры с этими функциями: [рецепты](cookbook.md).
- Если что-то не работает как ожидали: [ловушки и FAQ](gotchas.md).
