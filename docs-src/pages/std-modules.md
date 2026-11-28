---
title: Standard modules
order: 40.5
section: Reference
description: The modules you import from std/: fs, path, time, os, args, json, net, http and thread
---

Besides the prelude, which every program gets automatically, the standard library has modules that you import by name. They are built into the compiler, so there is nothing to install:

```zark fragment
import "std/fs" as fs;
import "std/json" as json;
```

Always give a module a name with `as`: its functions are then written `fs::list_dir(...)` and do not mix with your own names.

| Module | What is in it |
|---|---|
| `std/io` | readers for memory, files and connections; buffering and bounded input |
| `std/csv` | streaming CSV records |
| `std/fs` | file metadata, directories, walking a tree, copying, moving, removing, temporary directories |
| `std/path` | path strings: `join`, `base`, `dir`, `ext`, `stem`, `normalize`, `relative`, `absolute` |
| `std/time` | wall clock, `DateTime` with time zones, parsing and printing ISO 8601, `Stopwatch`, `sleep_ms` |
| `std/os` | running programs and capturing their output, environment variables, `cpu_count`, `exe_path` |
| `std/args` | command-line options with `--help` |
| `std/json` | JSON parsing with error positions, a tree you can query and build, and a streaming `Builder` |
| `std/net` | TCP sockets and DNS (see [networking and threads](net-threads.md)) |
| `std/http` | an HTTP/1.1 client and a small server |
| `std/thread` | threads, `Mutex`, `Cond`, `WaitGroup`, `Channel<T>` |

Like everything in Zark, nothing here allocates on its own: functions that return new strings or lists take an `Allocator`, and the results have a `deinit()` or are freed with that allocator.

## `std/io` and `std/csv`

`io::Reader` reads bytes from memory, files, or network connections. `File` and `Conn` have a `reader()` method; `File` also has `writer()`. `MemoryReader`, `LimitedReader`, and `BufferedReader` borrow their sources and buffers: keep them alive and in place while reading. `io::copy` copies to a `Writer` using caller-owned scratch storage.

`csv::Reader` reads records incrementally, including quoted fields, commas, and embedded newlines. `field(i)` returns a slice valid until the next `next()` or `deinit()`. Set `max_bytes` and `max_fields` to positive values to bound a record's decoded data and field count; zero means unlimited. The reader cannot resume after an error. `csv::write_record` writes a record to a `Writer`; a failed write may leave a partial record. See `examples/csv_summary.zk` for file input.

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

| Function | What it does |
|---|---|
| `info(p)`, `link_info(p)` | `Info{ kind, size, modified, mode }`; `kind` is `.File`, `.Dir`, `.Link` or `.Other` |
| `exists`, `is_dir`, `is_file` | |
| `list_dir(a, p)` | a `DirList` sorted by name: `for (auto e : d.slice()) { e.name; e.kind }` |
| `walk(a, root)`, `walk_all(a, root)` | every file below `root` (with directories for `walk_all`), as relative paths |
| `make_dir`, `make_dirs` | one directory, or with every missing parent |
| `remove_file`, `remove_dir`, `remove_all(a, p)` | |
| `move(from, to)`, `copy_file(from, to)`, `append_file(p, data)`, `set_mode(p, mode)` | |
| `cwd(a)`, `set_cwd(p)`, `temp_dir(a, prefix)` | |

Errors are the usual names: `error.NotFound`, `error.PermissionDenied`, `error.AlreadyExists`, `error.DirectoryNotEmpty`, `error.NotADirectory`. Whole files are read and written with the prelude's `read_file` and `write_file`.

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

`DateTime` has the fields `year, month, day, hour, minute, second, nsec, offset` (seconds east of UTC) and prints itself as ISO 8601. `now_utc()`, `now_local()`, `utc(t)`, `local(t)` and `from_unix(t, offset)` make one; `parse` reads `2026-11-20`, `2026-11-20T10:43`, `...:05.250Z` and `...+01:00`. `unix()`, `unix_ms()` and `mono_ns()` read the clocks.

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

`exec` finds the program through `PATH`, waits for it and returns `Output{ code, out, err }`; a program that does not exist gives `error.ProgramNotFound`. `exec_with` also takes `cwd` and `input` (written to the program's stdin). `shell(a, "cmd | cmd")` runs a line through `/bin/sh`. The rest: `set_env`, `unset_env`, `env_or(name, default)`, `pid()`, `exit(code)`, `exe_path(a)`, `args(a)`, `cpu_count()`.

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

In a real program call `p.parse()`, which reads the process arguments. `--help` (or `-h`) prints the usage and makes `parse` return `error.Help`; a wrong option prints a message and returns `error.UnknownOption` or `error.MissingValue`. Accepted forms: `--name`, `--name=value`, `--name value`, `-n value`, `-nvalue`, combined flags `-abc`, and `--` before arguments that start with `-`.

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

- Reading: `get(key)` and `at(i)` never fail; a missing member is a null value, so you can write chains. `as_str`, `as_i64`, `as_f64`, `as_bool` return an error when the type differs; `str_or`, `int_or`, `f64_or`, `bool_or` take a default. `items()` and `members()` iterate.
- Integers are read from the literal, so `as_i64` is exact beyond 2^53.
- Strings without escapes point into the input text: keep it alive as long as the tree.
- Printing: `println(*v)` gives compact JSON, `"{*v:p}"` indented; `stringify(a, v, pretty)` returns a string.
- Building: `object`, `array`, `string`, `number`, `integer`, `boolean`, `null_value`, then `set(key, v)` and `push(v)`.
- `Builder` writes JSON straight into a `List<u8>` without a tree: `begin_object`, `key`, `string`, `integer`, `number`, `boolean`, `null_value`, `value(tree)`, `end`.

Use an `Arena` for a parsed tree: everything is freed at once with `deinit()`.

## What next

- [Networking and threads](net-threads.md): `std/net`, `std/http` and `std/thread`.
- [Standard library reference](stdlib.md): the prelude.
