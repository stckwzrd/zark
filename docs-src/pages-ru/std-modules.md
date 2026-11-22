---
title: Стандартные модули
order: 40.5
section: Справочник
description: Модули, которые импортируются из std/: fs, path, time, os, args, json, net, http и thread
---

Кроме прелюдии, которую каждая программа получает автоматически, в стандартной библиотеке есть модули, которые подключаются по имени. Они встроены в компилятор, устанавливать ничего не нужно:

```zark fragment
import "std/fs" as fs;
import "std/json" as json;
```

Всегда давайте модулю имя через `as`: тогда его функции пишутся как `fs::list_dir(...)` и не смешиваются с вашими.

| Модуль | Что в нём |
|---|---|
| `std/fs` | метаданные файлов, каталоги, обход дерева, копирование, перемещение, удаление, временные каталоги |
| `std/path` | строки путей: `join`, `base`, `dir`, `ext`, `stem`, `normalize`, `relative`, `absolute` |
| `std/time` | часы, `DateTime` с часовыми поясами, разбор и печать ISO 8601, `Stopwatch`, `sleep_ms` |
| `std/os` | запуск программ с перехватом вывода, переменные окружения, `cpu_count`, `exe_path` |
| `std/args` | параметры командной строки с `--help` |
| `std/json` | разбор JSON с позицией ошибки, дерево для запросов и построения, потоковый `Builder` |
| `std/net` | TCP-сокеты и DNS (см. [сеть и потоки](net-threads.md)) |
| `std/http` | HTTP/1.1-клиент и небольшой сервер |
| `std/thread` | потоки, `Mutex`, `Cond`, `WaitGroup`, `Channel<T>` |

Как и всё в Zark, здесь ничего не выделяет память само: функции, возвращающие новые строки или списки, принимают `Allocator`, а у результата есть `deinit()` или его освобождают тем же аллокатором.

## `std/fs`

```zark run
import "std/fs" as fs;
import "std/path" as path;

!void main() {
    auto ar = Arena::init(c_allocator());
    defer ar.deinit();
    const auto a = ar.allocator();

    const auto dir = fs::temp_dir(a, "demo")?;
    defer fs::remove_all(a, dir) catch |e| {};
    fs::make_dirs(path::join(a, [dir, "src/util"])?)?;
    write_file(path::join(a, [dir, "src/main.zk"])?, "void main() {{}")?;
    write_file(path::join(a, [dir, "src/util/str.zk"])?, "")?;

    const auto files = fs::walk(a, dir)?;
    println(files.slice());
    const auto info = fs::info(path::join(a, [dir, "src/main.zk"])?)?;
    println(info.kind, info.size, fs::is_dir(path::join(a, [dir, "src"])?));
}
```

| Функция | Что делает |
|---|---|
| `info(p)`, `link_info(p)` | `Info{ kind, size, modified, mode }`; `kind` — `.File`, `.Dir`, `.Link` или `.Other` |
| `exists`, `is_dir`, `is_file` | |
| `list_dir(a, p)` | `DirList`, отсортированный по имени: `for (auto e : d.slice()) { e.name; e.kind }` |
| `walk(a, root)`, `walk_all(a, root)` | все файлы внутри `root` (у `walk_all` и каталоги) как относительные пути |
| `make_dir`, `make_dirs` | один каталог или вместе со всеми недостающими родителями |
| `remove_file`, `remove_dir`, `remove_all(a, p)` | |
| `move(from, to)`, `copy_file(from, to)`, `append_file(p, data)`, `set_mode(p, mode)` | |
| `cwd(a)`, `set_cwd(p)`, `temp_dir(a, prefix)` | |

Ошибки — обычные имена: `error.NotFound`, `error.PermissionDenied`, `error.AlreadyExists`, `error.DirectoryNotEmpty`, `error.NotADirectory`. Файл целиком читают и пишут функциями прелюдии `read_file` и `write_file`.

## `std/path`

```zark run
import "std/path" as path;

!void main() {
    const auto a = c_allocator();
    println(path::base("src/net/http.zk"), path::dir("src/net/http.zk"), path::ext("a.tar.gz"), path::stem("a.tar.gz"));
    println(path::join(a, ["src", "../lib", "x.c"])?, path::normalize(a, "/a/./b/../c//")?, path::relative(a, "/a/b/c", "/a/d")?);
}
```

## `std/time`

```zark run
import "std/time" as time;

!void main() {
    const auto launch = time::parse("2026-11-20T10:43:05+01:00")?;
    println(launch, launch.weekday(), launch.to_unix());
    println(time::utc(launch.to_unix()), launch.add_days(30));
    println("{launch:d}");
    auto sw = time::Stopwatch::start();
    time::sleep_ms(5);
    println(sw.ms() >= 5);
}
```

У `DateTime` поля `year, month, day, hour, minute, second, nsec, offset` (секунды к востоку от UTC), печатается он в ISO 8601. Создают его `now_utc()`, `now_local()`, `utc(t)`, `local(t)` и `from_unix(t, offset)`; `parse` читает `2026-11-20`, `2026-11-20T10:43`, `...:05.250Z` и `...+01:00`. Часы читают `unix()`, `unix_ms()` и `mono_ns()`.

## `std/os`

```zark run
import "std/os" as os;

!void main() {
    const auto a = c_allocator();
    auto r = os::exec(a, ["sh", "-c", "echo hello; echo oops >&2; exit 3"])?;
    defer r.deinit();
    println(r.code, str_trim(r.out), str_trim(r.err));

    auto sorted = os::exec_with(a, os::Command{ .argv = ["sort"], .input = "b\na\nc\n" })?;
    defer sorted.deinit();
    print(sorted.out);
}
```

`exec` ищет программу через `PATH`, ждёт её и возвращает `Output{ code, out, err }`; несуществующая программа даёт `error.ProgramNotFound`. `exec_with` принимает ещё `cwd` и `input` (пишется в stdin программы). `shell(a, "cmd | cmd")` выполняет строку через `/bin/sh`. Остальное: `set_env`, `unset_env`, `env_or(name, default)`, `pid()`, `exit(code)`, `exe_path(a)`, `args(a)`, `cpu_count()`.

## `std/args`

```zark run
import "std/args" as args;

!void main() {
    auto p = args::Parser::init(c_allocator(), "copy", "Copies files.");
    defer p.deinit();
    p.flag("verbose", 'v', "print every file")?;
    p.option("out", 'o', "target directory", ".")?;
    p.option("jobs", 'j', "parallel copies", "1")?;
    p.positional_usage("FILE...");
    p.parse_from(["-v", "a.txt", "--out=/tmp", "-j4", "b.txt"])?;
    println(p.has("verbose"), p.get("out"), p.get_int("jobs")?, p.rest());
}
```

В настоящей программе вызывайте `p.parse()`, он читает аргументы процесса. `--help` (или `-h`) печатает справку, и `parse` возвращает `error.Help`; неверный параметр печатает сообщение и возвращает `error.UnknownOption` или `error.MissingValue`. Поддерживаются формы `--name`, `--name=value`, `--name value`, `-n value`, `-nvalue`, слитные флаги `-abc` и `--` перед аргументами, начинающимися с `-`.

## `std/json`

```zark run
import "std/json" as json;

!void main() {
    auto ar = Arena::init(c_allocator());
    defer ar.deinit();
    const auto a = ar.allocator();

    const auto doc = json::parse(a, "{{\"name\": \"zark\", \"tags\": [\"fast\", \"small\"], \"stars\": 42}")?;
    println(doc.get("name").str_or("?"), doc.get("stars").int_or(0), doc.get("missing").get("x").is_null());
    for (auto t : doc.get("tags").items()) { print("{*t} "); }
    println("");

    json::ParseError pe;
    _ = json::parse_ex(a, "[1, 2,,]", &pe) catch null;
    println(pe);

    const auto o = json::object(a)?;
    o.set("ok", json::boolean(a, true)?)?;
    o.set("count", json::integer(a, 3)?)?;
    println(*o);
}
```

- Чтение: `get(key)` и `at(i)` никогда не падают; отсутствующий элемент — это null-значение, поэтому можно писать цепочки. `as_str`, `as_i64`, `as_f64`, `as_bool` возвращают ошибку, если тип другой; `str_or`, `int_or`, `f64_or`, `bool_or` принимают значение по умолчанию. `items()` и `members()` перебирают.
- Целые читаются из литерала, поэтому `as_i64` точен и за пределами 2^53.
- Строки без escape-последовательностей указывают в исходный текст: держите его живым, пока живо дерево.
- Печать: `println(*v)` даёт компактный JSON, `"{*v:p}"` — с отступами; `stringify(a, v, pretty)` возвращает строку.
- Построение: `object`, `array`, `string`, `number`, `integer`, `boolean`, `null_value`, затем `set(key, v)` и `push(v)`.
- `Builder` пишет JSON прямо в `List<u8>` без дерева: `begin_object`, `key`, `string`, `integer`, `number`, `boolean`, `null_value`, `value(tree)`, `end`.

Для разобранного дерева используйте `Arena`: всё освобождается разом через `deinit()`.

## Что дальше

- [Сеть и потоки](net-threads.md): `std/net`, `std/http` и `std/thread`.
- [Справочник стандартной библиотеки](stdlib.md): прелюдия.
