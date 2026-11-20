---
title: Сеть и потоки
order: 40.6
section: Справочник
description: std/thread (потоки, Mutex, Channel, parallel_for), std/net (TCP) и std/http (клиент с HTTPS, многопоточный сервер)
---

## `std/thread`

```vibe run
import "std/thread" as thread;

!void main() {
    auto hits = thread::AtomicI64{};
    thread::Thread[4] ts;
    for (auto i : 0..4) {
        ts[i] = thread::spawn([&hits]() -> void {
            for (auto k : 0..1000) { hits.add(1); }
        })?;
    }
    for (auto t : ts) { _ = t; }
    for (auto i : 0..4) { ts[i].join(); }
    println(hits.load());

    i64[8] squares;
    thread::parallel_for(8, 0, [&squares](i64 i) -> void { squares[i] = i * i; })?;
    println(squares);
}
```

`spawn` запускает замыкание в новом потоке. Замыкание хранит указатели на захваченные переменные, поэтому **дожидайтесь (`join`) каждого потока до того, как эти переменные выйдут из области видимости**. `spawn_fn(f, arg)` запускает обычную `fn(void*)`.

| Тип | Что это |
|---|---|
| `Thread` | `join()`, `detach()` |
| `Mutex` | `lock()`, `unlock()`, `try_lock()`; нулевое значение готово к работе |
| `Cond` | `wait(&m)`, `wait_ms(&m, ms)`, `signal()`, `broadcast()` |
| `AtomicI64` | `add(d)` (возвращает старое значение), `load()`, `store(x)`, `compare_swap(old, new)` |
| `WaitGroup` | `add(n)`, `done()`, `wait()` |
| `Channel<T>` | ограниченная очередь: `Channel<T>::create(a, capacity)`, `send(v)`, `recv()`, `try_recv()`, `close()`, `destroy()` |

`parallel_for(n, threads, body)` вызывает `body(i)` для каждого `i` из `0..n`, разделяя работу на `threads` потоков (0 — по одному на ядро), и возвращается, когда всё готово. Блокировки, каналы и `WaitGroup` нельзя копировать после начала работы: передавайте их через указатель (канал поэтому создаётся в куче).

```vibe run
import "std/thread" as thread;

!void main() {
    const auto jobs = thread::Channel<i64>::create(c_allocator(), 16)?;
    defer jobs.destroy();
    auto total = thread::AtomicI64{};
    auto worker = thread::spawn([&jobs, &total]() -> void {
        while (true) {
            const auto n = jobs.recv() catch { break; };   // error.Closed, когда очередь пуста и закрыта
            total.add(n * n);
        }
    })?;
    for (auto i : 1..11) { jobs.send(i)?; }
    jobs.close();
    worker.join();
    println(total.load());
}
```

## `std/net`

```vibe run
import "std/net" as net;
import "std/thread" as thread;

!void main() {
    auto l = net::listen("127.0.0.1", 0)?;      // порт 0: любой свободный
    const auto port = l.port();
    auto server = thread::spawn([&l]() -> void {
        auto c = l.accept() catch { return; };
        u8[256] buf;
        auto r = net::Reader::init(&c, buf[..]);
        const auto name = r.read_line() catch "";
        c.print("hello, {name}!\n") catch {};
        c.close();
    })?;

    auto c = net::connect_to("localhost", port)?;
    c.write_all("Vibe\n")?;
    u8[256] buf;
    auto r = net::Reader::init(&c, buf[..]);
    println(r.read_line()?);
    c.close();
    server.join();
    l.close();
}
```

- `listen(host, port)` даёт `Listener` с `accept()`, `port()` и `close()` (последний будит поток, заблокированный в `accept`).
- `connect_to(host, port)` даёт `Conn`: `read(buf)` (0 в конце), `write_all(s)`, `print(...)` с интерполяцией без выделений, `set_timeout(ms)`, `close_write()`, `close()`, `peer(buf)`.
- `Reader::init(&conn, buf)` буферизует чтение: `read_line()`, `read_exact(&list, n)`, `read_all(&list)`.
- Ошибки: `error.HostNotFound`, `error.ConnectionRefused`, `error.AddressInUse`, `error.TimedOut`, `error.ConnectionReset`.

## `std/http`

Клиент говорит на HTTP/1.1 по `http://` и `https://`. Для HTTPS используется системная библиотека OpenSSL (`libssl.so.3`), она загружается при первом обращении, так что дополнительные флаги линковки не нужны; сертификаты и имена хостов проверяются по системному хранилищу.

```vibe fragment
import "std/http" as http;

!void main() {
    const auto a = c_allocator();
    auto r = http::get(a, "https://example.com/")?;
    defer r.deinit();
    println(r.status, r.header("content-type"), r.body.len);

    auto p = http::post(a, "https://httpbin.org/post", "application/json", "{{\"x\": 1}")?;
    defer p.deinit();

    http::Header[1] hs = [http::Header{ .name = "Authorization", .value = "Bearer TOKEN" }];
    auto q = http::send(a, http::Request{ .method = "DELETE", .url = "https://api.example.com/item/7", .headers = hs[..], .timeout_ms = 5000 })?;
    defer q.deinit();
}
```

- Поля `Request`: `method` ("GET"), `url`, `headers`, `body`, `timeout_ms` (30000), `max_redirects` (5), `insecure` (без проверки сертификата), `ca_file` (доверять этим PEM-сертификатам вместо системного хранилища).
- `Reply`: `status`, `reason`, `headers`, `body`, `header(name)` (без учёта регистра), `ok()`, `deinit()`. Chunked-тела и редиректы обрабатываются.
- Ошибки: `error.UnsupportedScheme`, `error.InvalidUrl`, `error.CertificateInvalid`, `error.TlsUnavailable` (нет libssl) и сетевые ошибки выше.
- `url_encode(a, s)`, `url_decode(a, s)`, `parse_url(s)`.

Сервер выполняет обработчик в пуле потоков, держит соединения keep-alive и даёт каждому запросу свою арену:

```vibe run
import "std/http" as http;
import "std/thread" as thread;

!void main() {
    auto srv = http::Server::bind("127.0.0.1", 0)?;
    const auto port = srv.port();
    auto t = thread::spawn([&srv]() -> void {
        srv.serve(c_allocator(), 4, [](http::ServerRequest* req, http::ServerResponse* res) -> void {
            if (req.path == "/hello") {
                res.printf("text/plain", "hello, {req.param("name")}") catch {};
                return;
            }
            res.status = 404;
            res.text("not found") catch {};
        }) catch {};
    })?;

    u8[128] url;
    auto r = http::get(c_allocator(), bprint(url[..], "http://127.0.0.1:{port}/hello?name=web")?)?;
    println(r.status, r.body);
    r.deinit();
    srv.stop();
    t.join();
}
```

- `ServerRequest`: `method`, `path`, `query`, `headers`, `body`, `peer`, `header(name)`, `param(name)` (раскодированный параметр запроса) и `a` — аллокатор, который освобождается после возврата обработчика.
- `ServerResponse`: задайте `status` (200), `header(name, value)`, затем ровно один из `text`, `html`, `json`, `send(content_type, body)` или `printf(content_type, ...)`.
- `serve(a, threads, handler)` блокируется до `stop()`. Обработчик выполняется в нескольких потоках одновременно: защищайте общие данные `Mutex` или атомиками.
- Сервер говорит на обычном HTTP; для HTTPS ставьте его за обратный прокси (nginx, Caddy).
