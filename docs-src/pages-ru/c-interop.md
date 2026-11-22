---
title: Взаимодействие с C и C++
order: 30
section: Интероп и инструменты
description: extern, export, строки и указатели на границе с C, подключение .c, .cpp и библиотек, структуры, колбэки и фасад extern "C" в Zark
---

Zark не нужен отдельный «слой привязки»: C-функцию объявляют одной строкой, а C-файл передают компилятору в командной строке. Здесь собрано всё, что нужно на границе.

## Вызов C из Zark: `extern`

`extern` объявляет функцию, которая живёт снаружи. Сигнатура пишется в терминах Zark, а соответствие с C простое:

| C | Zark |
|---|---|
| `int`, `int32_t` | `i32` |
| `long`, `int64_t`, `ssize_t` | `i64` |
| `unsigned`, `uint32_t` | `u32` |
| `size_t`, `uint64_t` | `u64` |
| `char`, `uint8_t` | `u8` |
| `double` / `float` | `f64` / `f32` |
| `char *`, `const char *` | `u8*` |
| `void *` | `void*` |
| любой `T *` | `T*` |
| `void` (результат) | результат не пишется |
| `...` | `...` |

```zark run
extern i32 puts(u8* s);
extern i32 atoi(u8* s);
extern u64 strlen(u8* s);

void main() {
    puts("привет из C");
    println(atoi("41") + 1, strlen("abcd"));
}
```

Функции libc, которые часто нужны, уже объявлены в прелюдии (`printf`, `malloc`, `calloc`, `free`, `exit`, `memcpy`, `memset`, `strlen`, `sqrt`, `sin`, `cos`, `pow`, `floor`, `fopen`, `fork` и т. д.). Их можно просто вызывать, а объявлять заново не обязательно.

> **Ловушка.** Если вы объявите `extern` с именем, которое уже занято **функцией Zark** из прелюдии (`abs`, `min`, `max`, `sort`), будет ошибка «duplicate function». Выберите другой способ или импортируйте C-версию в обёртку с другим именем.

## Строки на границе

Литерал `"..."` всегда заканчивается нулевым байтом и поэтому подходит как `u8*` (то есть `const char *`):

```zark run
extern i32 puts(u8* s);

void main() {
    puts("литерал: можно передавать как есть");
}
```

Любой другой `str` (срез) ни на что не заканчивается и **не годится** как C-строка. Тип `str` — это `{ ptr, len }`, и в C уходит только `s.ptr`, который читается до нулевого байта:

```zark run
extern i32 puts(u8* s);

void main() {
    const auto name = "abc";
    const auto part = name[0..2];
    puts(part.ptr);
}
```

Ожидали `ab`, а получили `abc`: после `ab` нет нулевого байта, и C читает дальше. Для таких строк нужна C-строка. Есть два способа:

- `to_cstr(buf, s)` — копирует в **ваш** буфер и добавляет нулевой байт (без выделения памяти);
- `a.dupz(s)` — копирует в куче через аллокатор.

```zark run
extern i32 puts(u8* s);

!void main() {
    const auto name = "abcdef";
    const auto part = name[0..3];

    u8[16] buf;
    const auto c1 = to_cstr(buf[..], part)?;
    puts(c1);

    const auto a = c_allocator();
    const auto c2 = a.dupz(part)?;
    defer a.free(c2[0..part.len + 1]);
    puts(c2);
}
```

Обратно: `cstr(p)` превращает C-строку `u8*` в `str` (длина считается через `strlen`, копирования нет):

```zark run
extern u8* getenv(u8* name);

void main() {
    const auto p = getenv("PATH");
    if (p != null) {
        const auto s = cstr(p);
        println(s.len > 0);
    }
    const auto q = getenv("ЭТО_НЕ_ЗАДАНО");
    println(q == null);
}
```

## Указатели

Любой указатель Zark приводится к `void*` и обратно **неявно**; к другим типам указателей — через `as`:

```zark run
void main() {
    i64 x = 258;
    const auto p = &x as *u8;
    println(p[0], p[1]);
}
```

Массив или срез превращается в указатель на первый элемент через `.ptr` (у срезов) или `&a[0]`/`as T*`:

```zark run
extern void* memset(void* dst, i32 c, u64 n);

void main() {
    u8[8] buf;
    memset(buf[..].ptr as *void, 65, 4);
    println(buf);
}
```

## Переменные число аргументов

`...` в `extern` допускает вариативные функции. Типы подтягиваются по обычным правилам C: целые расширяются, `f32` → `f64`. Срезы запрещены.

```zark run
extern i32 printf(u8* fmt, ...);

void main() {
    printf("%d %s %.2f\n", 5, "str", 2.5);
}
```

Для вывода из самого Zark лучше `println`: он безопаснее. `printf` пригодится при работе с готовым C-кодом.

## Структуры

Структуры Zark лежат в памяти так же, как C-структуры (те же размеры и выравнивание). Поэтому описание на стороне Zark — копия описания на C.

Структуры можно передавать в `extern`-функции и получать из них **по значению**, как в C: компилятор следует правилам System V x86-64 (маленькие структуры идут в регистрах, большие — через стек или скрытый указатель) на всех бэкендах. Это нужно библиотекам вроде raylib: `extern void DrawCircleV(Vector2 center, f32 radius, Color color);` работает как написано. Передача по указателю тоже работает:

```zark file=vec.c
typedef struct { double x, y, z; } Vec3;

double vec3_dot(const Vec3 *a, const Vec3 *b) {
    return a->x * b->x + a->y * b->y + a->z * b->z;
}

void vec3_scale(Vec3 *v, double k) {
    v->x *= k;
    v->y *= k;
    v->z *= k;
}
```

```zark run with=vec.c
struct Vec3 { f64 x; f64 y; f64 z; }

extern f64 vec3_dot(Vec3* a, Vec3* b);
extern void vec3_scale(Vec3* v, f64 k);

void main() {
    auto a = Vec3{ .x = 1.0, .y = 2.0, .z = 3.0 };
    auto b = Vec3{ .x = 4.0, .y = 5.0, .z = 6.0 };
    println(vec3_dot(&a, &b));
    vec3_scale(&a, 10.0);
    println(a);
}
```

По значению:

```zark file=v2.c
typedef struct { float x, y; } Vector2;
typedef struct { unsigned char r, g, b, a; } Color;

Vector2 v2_add(Vector2 a, Vector2 b) { Vector2 r = { a.x + b.x, a.y + b.y }; return r; }
Color fade(Color c, float k) { Color o = { c.r, c.g, c.b, (unsigned char)(c.a * k) }; return o; }
```

```zark run with=v2.c
struct Vector2 { f32 x; f32 y; }
struct Color { u8 r; u8 g; u8 b; u8 a; }

extern Vector2 v2_add(Vector2 a, Vector2 b);
extern Color fade(Color c, f32 k);

void main() {
    println(v2_add(Vector2{ .x = 1.0, .y = 2.0 }, Vector2{ .x = 3.0, .y = 4.0 }));
    println(fade(Color{ .r = 255, .g = 128, .b = 0, .a = 200 }, 0.5));
}
```

## Подключение C-файлов

`zark run`, `zark build` и `zark test` принимают `.c`, `.cpp`, `.o`, `.a`, `.so` и ключи `-l...` / `-L...` вместе с исходником:

```sh
zark run main.zk mathlib.c                 # компилирует mathlib.c и линкует
zark run main.zk mathlib.c engine.cpp      # с C++ линковка идёт через clang++
zark build main.zk lib.o -lm -o app        # готовый объект и библиотека
```

Что происходит: каждый `.c` / `.cpp` компилируется через `clang` (`clang++` для C++, уровень оптимизации берётся из `-O`), затем всё линкуется вместе с вашей программой. Если есть хотя бы один `.cpp`, линковщиком становится `clang++`.

Подробности режимов — в [инструментах](tooling.md#режимы-компиляции).

## Вызов Zark из C: `export`

`export` выводит функцию Zark под её собственным именем. C-код её видит как обычный внешний символ:

```zark file=sumsq.c
#include <stdint.h>

extern int64_t zark_square(int64_t x);

int64_t c_sum_squares(int64_t n) {
    int64_t s = 0;
    for (int64_t i = 1; i <= n; i++) s += zark_square(i);
    return s;
}
```

```zark run with=sumsq.c
extern i64 c_sum_squares(i64 n);

export i64 zark_square(i64 x) {
    return x * x;
}

void main() {
    println(c_sum_squares(10));
}
```

Имена `extern` и `export` — символы C, поэтому **не получают префикса** модуля, даже при `import ... as` (см. [модули](modules.md)).

## Колбэки: указатели на функции

Функцию Zark можно передать в C как `fn(...) -> R`. Это обычный адрес функции без замыкания:

```zark run
extern void qsort(void* base, u64 n, u64 size, fn(void*, void*) -> i32 cmp);

i32 cmp(void* a, void* b) {
    const auto x = *(a as *i64);
    const auto y = *(b as *i64);
    if (x < y) { return -1; }
    if (x > y) { return 1; }
    return 0;
}

void main() {
    auto xs = [5, 3, 9, 1, 7];
    qsort(xs[..] as *void, 5, 8, cmp);
    println(xs);
}
```

Замыкание `fn[](...) -> R` в C передавать нельзя: у него есть контекст, а C ждёт простой адрес.

## C++ через фасад `extern "C"`

Zark не знает C++-ABI (шаблоны, перегрузки, классы). Поэтому C++ прячут за небольшим C-интерфейсом, где объект — непрозрачный указатель.

```zark file=engine.cpp
#include <vector>
#include <algorithm>
#include <cstdint>

struct Engine { std::vector<double> v; };

extern "C" {
    void *engine_new() { return new Engine; }
    void engine_push(void *e, double x) { static_cast<Engine *>(e)->v.push_back(x); }
    double engine_median(void *e) {
        auto &v = static_cast<Engine *>(e)->v;
        std::sort(v.begin(), v.end());
        return v.empty() ? 0 : v[v.size() / 2];
    }
    void engine_free(void *e) { delete static_cast<Engine *>(e); }
}
```

```zark run with=engine.cpp
extern void* engine_new();
extern void engine_push(void* e, f64 x);
extern f64 engine_median(void* e);
extern void engine_free(void* e);

void main() {
    const auto e = engine_new();
    defer engine_free(e);
    for (auto x : [5.0, 1.0, 9.0, 3.0, 7.0]) {
        engine_push(e, x);
    }
    println(engine_median(e));
}
```

`defer` здесь гарантирует `engine_free` на любом выходе.

## Библиотеки: `-l` и `-L`

Подключение системных библиотек — как в C. Ключи `-l` и `-L` и файлы `.a`, `.so`, `.o` передаются линковщику как есть:

```sh
zark run main.zk -lm
zark run main.zk -L/opt/foo/lib -lfoo
zark build main.zk libbar.a -o app
```

Математика (`sqrt`, `sin`, `pow`) линкуется автоматически: `-lm` уже включён.

## Правила и подводные камни

- Нет `@cImport` и разбора заголовков: сигнатуры пишете руками. Это место для ошибок: тип вашего `extern` обязан совпадать с C.
- Структуры по значению переходят границу только через объявления `extern`. Если C-библиотека вызывает Zark (функция `export` или указатель на функцию), структуры нужно принимать по указателю.
- `bool` в C — это `_Bool`/`uint8_t`. Используйте `u8` или `i32`, а не `bool`, если сомневаетесь.
- Не передавайте `str` вместо `u8*`: нужна `s.ptr` (и нулевой байт, см. выше).
- `size_t` — это `u64`, `ssize_t` — `i64`.
- Память, которую вернула C-функция (`malloc`), освобождайте C-функцией (`free`), а не аллокатором Zark.
- `extern` с тем же именем, что и функция из прелюдии Zark, недопустимо.

## Что дальше

- Файлы и процессы: [справочник](stdlib.md).
- Режимы сборки и флаги: [инструменты](tooling.md).
